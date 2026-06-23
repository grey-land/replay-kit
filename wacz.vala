namespace ReplayView {
    
    public class WaczPage : GLib.Object {

        public string  url   { get; set; }
        public string  id    { get; set; }
        public string  title { get; set; }
        public int     size  { get; set; }
        public string  ts    { get; set; }
        public string  text  { get; set; }
        
		public unowned WaczFile parent { get; set; }
        public string  base_uri { get; set; default = ""; }

        public GLib.DateTime stamp() {
            return new GLib.DateTime.from_iso8601(ts, null);
        }
        
		public string repr() {
            return "<%s, %s (id:%s, ts:%s)>".printf( title, url, id, ts);
		}

		public string reverse() {
			return "%s/%s/%s".printf( base_uri, parent.get_id(), id );
		}

		
    }
    

    public class WaczFile : GLib.Object {

        public GLib.File file {get; protected set; }
		public GLib.ListStore pages {get; protected set; }
        public string  base_uri { get; set; default = ""; }

        public WaczFile( GLib.File file ) {
            this.file = file;
            this.pages = new GLib.ListStore( typeof (WaczPage) );
        }
        
		/**
		 * Get id of {@link ReplayView.WaczFile}. 
		 */
		public string get_id () {
			return file.get_basename().split(".")[0].replace(" ", "");
		}

		/**
		 * Get url where {@link ReplayView.WaczFile} will be served (localhost).
		 */
		public string reverse() {
			return "%s/%s".printf( base_uri, get_id() );
		}

		/**
		 * Get page by position.
		 */
		public WaczPage get_page (uint pos) {
			return (WaczPage) pages.get_item(pos);
		}

		/**
		 * Get page position by id.
		 */
        public bool find_page_id (string page_id, out uint pos ) {
			for ( uint i = 0; i < pages.get_n_items (); i++) {
				var page = (WaczPage) pages.get_item(i);
				if ( page.id == page_id ) {
					pos = i;
			        return true;
				}
			}
			return false;
		}

		/**
		 * Get page position by url.
		 */
		public bool find_page_url (string page_url, out uint pos ) {
			for ( uint i = 0; i < pages.get_n_items (); i++) {
				var page = (WaczPage) pages.get_item(i);
				if ( page.url == page_url ) {
					pos = i;
			        return true;
				}
			}
			return false;
		}

		/**
		 * Load pages of wacz archive.
		 * 
		 * Iterates through {@link ReplayView.WaczFile.file} archive, until *pages/pages.jsonl* is found. 
		 * Parse each line, and fills {@link ReplayView.WaczFile.pages} with {@link ReplayView.WaczPage} items.   
		 */
		public void parse_pages () throws Error {

			Archive.Read archive = new Archive.Read ();
			archive.support_format_all ();
            
			if (archive.open_filename ( file.get_path(), 10240) != Archive.Result.OK) {
				throw new GLib.IOError.INVALID_DATA(
					"Error opening %s: %s (%d)".printf( file.get_path(), archive.error_string(), archive.errno() )
				);
			}

			unowned Archive.Entry entry;
			Archive.Result last_result;

			while ((last_result = archive.next_header (out entry)) == Archive.Result.OK) {

				switch ( entry.pathname() ) {
						
					// TODO: parse datapackage-digest.json and validate checksum of datapackage.json.
					// case "datapackage-digest.json":

					// TODO: parse datapackage.json and extract warc file info and pages/pages.jsonl checksum.
					// Then validate checksum before deserialize pages.
					// case "datapackage.json":
					
					case "pages/pages.jsonl":
						
						// create temporary file to extract pages/pages.jsonl
						FileIOStream iostream;
						File _file = File.new_tmp("tpl-XXXXXX.pages.jsonl", out iostream);

						// extract content
						extract_archive_entry( _file, archive );

						// open new read-only file stream for temp file
						FileStream inp = FileStream.open (_file.get_path(), "r");

						// read first line, e.g:
						// {"format":"json-pages-1.0","id":"pages","title":"All Pages","hasText":true}
						string? line = null;
						if ((line = inp.read_line ()) != null) {
							
							// Read rest of lines, parse them, 
							// and load WaczPage objects.
							while ((line = inp.read_line ()) != null) {
								try {
									// Deserialize line to Warc Page
									Json.Node? node = Json.from_string(line);
									assert (node != null);
									
									WaczPage wacz_page = Json.gobject_deserialize (typeof (WaczPage), node) as WaczPage;
									assert (wacz_page != null);
									
									// Set Warc Page to Warc File relationship
									wacz_page.parent = this;

									// add to list
									pages.append(wacz_page);

								} catch (Error e) {
									warning(e.message);
								}
							}
						}
						break;

					default:
						break;
				}
				
			}

			if (last_result != Archive.Result.EOF) {
				//  throw new GLib.IOError.FAILED( "(%d) %s".printf(archive.errno(), archive.error_string()) );
				warning( "!Archive.Result.EOF (%d) %s".printf(archive.errno(), archive.error_string()) );
			}
        }


        private void extract_archive_entry( File output, Archive.Read archive ) throws Error {
            
			FileStream outstream = FileStream.open ( output.get_path(), "w");
            
			if ( outstream == null )
                throw new GLib.IOError.FAILED("Unable to extract warc file");
            
            if ( archive.read_data_into_fd ( outstream.fileno() ) != Archive.Result.OK )
                throw new GLib.IOError.FAILED("Unable to extract warc file");

        }


    }

}
