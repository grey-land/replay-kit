namespace ReplayView {
    
    /**
	 * ReplayServer
	 *
	 * In wacz file mode, it will serve wabac service worker
	 * (https://github.com/webrecorder/wabac.js/blob/main/dist/sw.js) and a
	 * replay.html where it redisters the service worker and helper functions
	 * to interact with wacz files.
	 *
	 */
	public class ReplayServer : Soup.Server {
        
        private GLib.ListStore _archives;
        private string _base_uri = "";
        
        private const string REPLAY_TMPL = """
            <!doctype html>
            <html>
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        body            { margin: 0; }
                        replay-web-page { display: block; height: 100vh; width: 100vw; border: none; }

                        /* custom scrollbar styling  https://css-tricks.com/custom-scrollbars-in-webkit/ 
                        ::-webkit-scrollbar {
                            width: 12px;
                        }
                        ::-webkit-scrollbar-track {
                            -webkit-box-shadow: inset 0 0 6px rgba(0,0,0,0.3);
                            border-radius: 10px;
                        }
                        ::-webkit-scrollbar-thumb {
                            border-radius: 10px;
                            -webkit-box-shadow: inset 0 0 6px rgba(0,0,0,0.5);
                        } */
                    </style>
                    <script src="/ui.js"></script>
                </head>
                <body>
                    %s
                </body>
            </html>
            """;
        
        public ReplayServer() {
            _archives = new GLib.ListStore( typeof(WaczFile) );
			
            // serve static files
			add_handler ("/sw.js",      handle_static);
			add_handler ("/ui.js",      handle_static);
            
            // serve archives 
			add_handler ("/archive/",   handle_archive);
			
            // serve archive pages
			add_handler ("/page/",      handle_page);
			
            // default handler - no need
            //  add_handler ("/",           handle_main);
		}

        public string base_uri() {
            return _base_uri;
        }
        
        public GLib.ListModel get_archives() {
            return _archives;
        }

        public WaczFile get_archive ( uint pos ) {
            return (WaczFile) _archives.get_item(pos);
        }

        public bool find_archive_id (string archive_id, out uint pos ) {
			for ( uint i = 0; i < _archives.get_n_items (); i++) {
				var wczf = (WaczFile) _archives.get_item(i);
				if ( wczf.get_id() == archive_id ) {
					pos = i;
			        return true;
				}
			}
			return false;
		}

        public WaczFile add_archive(GLib.File file) throws Error {
            var archive = new WaczFile(file);
            archive.base_uri = archive_root();
            archive.parse_pages();
            for ( int i = 0; i < archive.pages.get_n_items () ; i++) {
                var page = (WaczPage) archive.pages.get_item(i);
                page.base_uri = page_root();
            }
            _archives.append(archive);
            return archive;
        }


		/**
         * bind
         *
         * Binds soup server at provided port for localhost and sets base_uri.
         * By default random port is used (port=0).
         */
        public bool bind (int port = 0) {
            try {
                listen_local (port, Soup.ServerListenOptions.IPV4_ONLY);
                foreach (Uri uri in get_uris ())
                    _base_uri = uri.to_string ();
                message ("[ReplayServer] Listen on %s", _base_uri);
                return true;
            } catch (GLib.Error e) {
                warning (e.message);
                return false;
            }
        }
        
        private string page_root() {
            return "%spage".printf(_base_uri);
        }

        private string archive_root() {
            return "%sarchive".printf(_base_uri);
        }

        private void handle_static(Soup.Server server, Soup.ServerMessage msg, string path, GLib.HashTable<string, string>? query) {
            set_file_response(msg, 
                File.new_for_uri(
                    "resource://io/gitlab/vgmkr/replay-view/assets/%s".printf(path.substring(1))));
        }

        private void handle_archive(Soup.Server server, Soup.ServerMessage msg, string path, GLib.HashTable<string, string>? query) {
            string[] parts = path.split("/");
            if ( parts.length > 2 ) {
                uint archive_pos;
                if ( find_archive_id( parts[2], out archive_pos ) ) {
                    set_file_response(msg, get_archive(archive_pos).file);
                }
            }
        }

        private void handle_page(Soup.Server server, Soup.ServerMessage msg, string path, GLib.HashTable<string, string>? query) {
            string[] parts = path.split("/");
                        
            if ( parts.length > 3 ) { // parts = ["", "pages", "<archive id>", "<page id>"]

                uint archive_pos;
                if ( find_archive_id( parts[2], out archive_pos ) ) {

                    WaczFile archive = get_archive(archive_pos);
                                
                    uint page_pos;
                    if ( archive.find_page_id(parts[3], out page_pos ) ) {
                        
                        WaczPage page = archive.get_page(page_pos);

                        string block = REPLAY_TMPL.printf("""
                                            <replay-web-page 
                                                replayBase="/"
                                                source="%s" 
                                                url="%s"
                                                embed="replayonly">
                                            </replay-web-page>
                                            """.printf( archive.reverse(), page.url )
                                        );

                        msg.set_status(200, "OK");
                        msg.set_response("text/html", Soup.MemoryUse.COPY, block.data);
                    }
                }
            }
        }
        

        
        /**
         * Send file back to client with support for http range response.
         */
        protected void set_file_response(Soup.ServerMessage msg, File file, string? mimetype = null, GLib.Cancellable? cancellable = null ) {

            string file_mime = mimetype ?? "application/octet-stream";
            int64  file_size = 0;

            // Try to read mime type and file size
            try {
                FileInfo info = file.query_info("*", 0);
                file_size = info.get_size();
                file_mime = info.get_content_type();
            } catch (GLib.Error e) {
                stderr.printf("Error: %s\n", e.message);
            }

            var res_headers = msg.get_response_headers();

            switch ( msg.get_method() ) {

                // For HEAD requests, notify client that we
                // support range requests
                case "HEAD":
                    msg.set_status(200, "OK");
                    res_headers.append("Accept-Ranges", "bytes");
                    res_headers.set_content_length(file_size);
                    break;

                // For GET requests
                case "GET":

                    var req_headers = msg.get_request_headers();

                    int64 start = 0;
                    int64 end   = file_size;

                    //  CVE-2026-2443
                    // https://gitlab.gnome.org/GNOME/libsoup/-/work_items/516
                    //  // Parse range header, if any, and
                    //  // respond with appropriate status code
                    //  // and content headers
                    //  Soup.Range[] ranges;
                    //  if ( req_headers.get_ranges(0, out ranges) ) {
                    //      if ( ranges.length > 0 ) {
                    //          start = ranges[0].start;
                    //          if ( ranges[0].end >= file_size ) {
                    //              end = file_size - 1;
                    //          } else {
                    //              end = ranges[0].end;
                    //          }
                    //          msg.set_status(206, "Partial Content");
                    //          res_headers.set_content_range(start, end, file_size);
                    //          res_headers.set_content_length(end - start + 1);
                    //      }
                    //  } else {
                    //      msg.set_status(200, "OK");
                    //      res_headers.set_content_length(file_size);
                    //  }

                    // Manual parsing of the Range header
                    bool is_partial = false;
                    string? range_header = req_headers.get_one("Range");
                    if (range_header != null && range_header.has_prefix("bytes=")) {
                        string spec = range_header.substring(6).strip();
                        // Split by comma in case of multi-range (we only process the first range)
                        string[] parts = spec.split(",");
                        if (parts.length > 0) {
                            string[] bounds = parts[0].split("-", 2);
                            if (bounds.length == 2) {
                                string start_str = bounds[0].strip();
                                string end_str = bounds[1].strip();

                                if (start_str == "" && end_str != "") {
                                    // Suffix range request: e.g., bytes=-500 (get last 500 bytes)
                                    int64 suffix_len = int64.parse(end_str);
                                    if (suffix_len > file_size) {
                                        suffix_len = file_size;
                                    }
                                    start = file_size - suffix_len;
                                    end = file_size - 1;
                                    is_partial = true;
                                } else if (start_str != "") {
                                    // Standard range: e.g., bytes=500- or bytes=500-999
                                    start = int64.parse(start_str);
                                    if (end_str != "") {
                                        end = int64.parse(end_str);
                                    }
                                    
                                    // Prevent out-of-bounds math
                                    if (start < 0) start = 0;
                                    if (end >= file_size || end < start) {
                                        end = file_size - 1;
                                    }
                                    is_partial = true;
                                }
                            }
                        }
                    }

                    if ( is_partial ) {
                        msg.set_status(206, "Partial Content");
                        res_headers.set_content_range(start, end, file_size);
                        res_headers.set_content_length(end - start + 1);
                    } else {
                        //  start = 0;
                        //  end = file_size - 1;
                        msg.set_status(200, "OK");
                        res_headers.set_content_length(file_size);
                    }
                

                    
                    res_headers.append("Accept-Ranges", "bytes");

                    // Then stream content back to client
                    try {

                        bool done = false;
                        ssize_t bytes_read = 0;
                        size_t BUFFER_SIZE = 1024 * 4;

                        FileInputStream stream = file.read(cancellable);

                        if ( start > 0 ) {
                            stream.seek(start, GLib.SeekType.CUR, cancellable);
                        }
                        
                        //  stderr.printf("\t\t~ stream [%d:%d]\n", (int) start, (int) end);

                        while ( ! done ) {

                            int64 pos = stream.tell();

                            // Make sure BUFFER_SIZE does not exceed requested Range
                            if ( end + 1 - pos < BUFFER_SIZE ) {
                                BUFFER_SIZE = (size_t) ( end + 1 - pos ).to_little_endian();
                                done = true;
                            }

                            // Create buffer with appropriate size
                            uint8[] buffer = new uint8[BUFFER_SIZE];

                            // Read into buffer
                            bytes_read = stream.read(buffer, cancellable);
                            if ( bytes_read == 0 ) {
                                done = true;
                            } else {
                                // Send the buffer content as needed
                                msg.set_response( file_mime, Soup.MemoryUse.COPY, buffer[0:bytes_read]);
                            }

                        }
                    } catch (GLib.Error e) {
                        stderr.printf("Error: %s\n", e.message);
                    }
                    break;

                default:
                    break;
            }
        }

	}

}