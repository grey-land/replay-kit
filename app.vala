
namespace Replay {

    [GtkTemplate (ui = "/io/gitlab/vgmkr/replay-kit/assets/app-page.ui")]
    class PageBin : Gtk.Box {
        
        [GtkChild] private unowned Gtk.CheckButton check;
        [GtkChild] private unowned Gtk.Label title;
        [GtkChild] private unowned Gtk.Label subtitle;
        [GtkChild] private unowned Gtk.Label date;

        public PageBin( Gtk.ListItem li ) {
             
            var page = li.get_item() as WaczPage;
            if ( page != null ) {

                title.set_label( page.title );
                subtitle.set_label( page.url );
                date.set_label( page.ts );
            }
            
            li.bind_property("selected", check, "active");

        }

    }

    [GtkTemplate (ui = "/io/gitlab/vgmkr/replay-kit/assets/app-window.ui")]
    public class Window : Adw.ApplicationWindow {
        
        public WaczPage page { 
            get { 
                return _page; 
            }
            protected set { 
                _page = value;
                if ( _page != null ) {
                    view.set_sensitive(true);
                    view.load_uri( _page.reverse() );
                    set_title(_page.title);
                }
            }
        }

        private WebKit.WebView view;
        private WaczPage? _page = null;

        [GtkChild] private unowned Gtk.Label report_label;
        [GtkChild] private unowned Gtk.SingleSelection selection;
        [GtkChild] private unowned Adw.ToolbarView toolbar;
        [GtkChild] private unowned Adw.BottomSheet bottomsheet;
        [GtkChild] private unowned Gtk.ScrolledWindow list_scroll;

        public void set_pages(GLib.ListModel? model) {
            selection.set_model( model );
        }

        public Window(App app) {
            
            Object(application: app);
            set_default_size(1280, 800);
            set_title("ReplayView");
            
            // WEB VIEW
            view = new WebKit.WebView();
            
            // Don't allow clicks by default on webview. 
            // When Webview is on default empty page, and user clicks,
            // will render a white backround which looks ugly in dark theme.   
            // Sensitivity will be enables once `this.page` is set.
            view.set_sensitive(false);

            // handle mouse hover and update ui
            view.mouse_target_changed.connect( on_mouse_target );

            // set custom actions to context-menu 
            view.context_menu.connect( on_context_menu );

            // enable debugging
            view.get_settings().set_enable_developer_extras(true);
            // Register javascript user message handler
            //  if ( view.user_content_manager
            //          .register_script_message_handler_with_reply("warc", null ) ) {
            //      view.user_content_manager
            //          .script_message_with_reply_received
            //          .connect( on_message );
            //  }
             
            toolbar.set_content(view);

            // Force bottom sheet height to 50% of window height
            bind_property("default-height", list_scroll, "height-request", 
                BindingFlags.SYNC_CREATE, 
                (binding, source_value, ref target_value) => {
                    int window_height = source_value.get_int();
                    target_value.set_int(window_height / 2);
                    return true;
                }
            );
        }
        
        public void load_page( WaczPage? _page ) {
            page = _page;
            bottomsheet.set_open(false);
        }

        //  [GtkCallback]
        //  private void on_realize() {
        //      message("REALIZED");
        //  }

        /**
         * Callback to display context menu.
         */
        private bool on_context_menu ( WebKit.ContextMenu ctx_menu, WebKit.HitTestResult hit) {
            ctx_menu.prepend( new WebKit.ContextMenuItem.separator() );
            //  if ( hit.context_is_image () )
            //      ctx_menu.prepend(
            //          new WebKit.ContextMenuItem.from_gaction (
            //              action_request_extract_link, "Extract Image", hit.image_uri.strip() ) );
            //  if ( hit.context_is_media () )
            //      ctx_menu.prepend(
            //          new WebKit.ContextMenuItem.from_gaction (
            //              action_request_extract_link, "Extract Media", hit.media_uri.strip() ) );
            //  if ( hit.context_is_link () )
            //      ctx_menu.prepend(
            //          new WebKit.ContextMenuItem.from_gaction (
            //              action_request_extract_link, "Extract Link", hit.link_uri.strip() ) );
            //  if ( hit.context_is_selection () )
            //      //  message("\t\t[context_is_selection]");
            //      ctx_menu.prepend(
            //          new WebKit.ContextMenuItem.from_gaction (
            //              action_request_caption, "Link Caption", null ) );
            return false;
        }

        
        [GtkCallback]
        private void on_page_bind ( GLib.Object obj ) {
            var li = ( Gtk.ListItem ) obj;
            li.set_child( new PageBin(li) );
        }

        [GtkCallback]
        private void on_page_teardown ( GLib.Object obj ) {
            var li  = obj as Gtk.ListItem;
            li.set_child(null);
        }

        //  [GtkCallback]
        //  private void on_page_activate ( uint pos ) {
        //      //  var page = (WaczPage) selection.get_item(pos);
        //      //  load_page(page);
        //  }

        [GtkCallback]
        public void on_page_select(uint pos, uint n_items) {
            load_page( selection.get_selected_item () as WaczPage );
        }

        private void uri_updated() {
            set_title( view.get_title() );
            notify_property("title");
        }

        [GtkCallback]
        private void request_file_open () {
            
            var file_dialog = new Gtk.FileDialog ();
            
            file_dialog.default_filter = new Gtk.FileFilter();
            file_dialog.default_filter.set_filter_name("Wacz files");
            //  file_dialog.default_filter.add_mime_type("application/zip");
            file_dialog.default_filter.add_suffix("wacz");
            file_dialog.default_filter.add_suffix("wacz.gz");

            file_dialog.set_title("Select Wacz Archive");
            file_dialog.open_multiple.begin (null, null, (obj, res) => {
                try {
                    ListModel files = file_dialog.open_multiple.end(res);

                    var _app = (App) application;

                    for ( uint i = 0; i < files.get_n_items(); i ++ ) {
                        
                        var _file = files.get_item(i) as GLib.File;

                        if ( i == 0 ) {
                            var archive = _app.add_archive(_file);
                            set_pages( archive.pages );
                            bottomsheet.set_open(true);
                        } else {
                            _app.open({ _file }, "internal");
                        }
                    }
                } catch (Error e) {
                    warning ("Error while opening file: %s ...", e.message);
                }
            });
        
        }

        

        /**
         * Callback to render bottom report line.
         */
        private void on_mouse_target  (WebKit.HitTestResult hit, uint modifiers) {
            if ( hit.context_is_image () ) {
                report_label.set_label( "[Image]: %s".printf( hit.image_uri.strip() ) );
            } else if ( hit.context_is_media () ) {
                report_label.set_label( "[Media]: %s".printf( hit.media_uri.strip() ) );
            } else if ( hit.context_is_link () ) {
                report_label.set_label( "%s".printf( hit.link_uri.strip() ) );
            } else if ( hit.context_is_selection () ) {
                report_label.set_label("[selection]");
            } else {
                report_label.set_label("");
            }
        }
        
    }

    /**
     * Application to replay web archives.
     */     
    public class App : Adw.Application {

        private Server server;
        private int server_port = 0; // use 0 for random port
        
        public App() {
            Object (
                application_id: "io.gitlab.vgmkr.replay-kit",
                resource_base_path: "/io/gitlab/vgmkr/replay-kit",
                flags: ApplicationFlags.HANDLES_OPEN
            );
            server = new Server();
            server.bind( server_port );
        }
        
        public WaczFile add_archive(GLib.File file) throws Error {
            return server.add_archive(file);
        }

        protected override void open (GLib.File[] files, string hint ) {
            foreach ( GLib.File file in files ) {
                try {   
                    var archive = add_archive(file);
                    var win = new Window(this);
                    win.set_pages( archive.pages );
                    win.present();
                } catch ( GLib.Error e ) {
                    warning(e.message);
                }
            }
        }

        protected override void activate () {
            if ( this.active_window == null ) {
                var win = new Window(this);
                win.present();
            } else {
                this.active_window.present ();
            }
        }
      
    }

    public static int main (string[] args) {
        var app = new App();
        return app.run(args);
    }

}

