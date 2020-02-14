# dcgi
Simple and light [CGI](https://en.wikipedia.org/wiki/Common_Gateway_Interface) library for D. [Documentation](https://dcgi.dpldocs.info/dcgi.html)

## Basic example
 
```d
import dcgi;

mixin DCGI; // Needed for boilerplate code

void cgi(Request req, Output output) 
{
  output("Hello, world");
}
```

## Full example

```d
/+ dub.sdl:
name "Hello_dcgi"
description "A minimal dcgi application."
dependency "dcgi" version="~>0.1.0"
+/

import dcgi;

mixin DCGI!my_cgi_function; // Custom function

@DisplayExceptions // Show exceptions directly on output
@MaxRequestBodyLength(1024) // Limit request body to 1kb
void my_cgi_function(Request request, Output output) 
{
  output.status = 201; // Default is 200
  output.addHeader("content-type", "text/plain"); // Default is text/html
  output("Hello, world");
  
  if ("REQUEST_URI" in request.header)
    output("Uri:", request.header["REQUEST_URI"]);
}
```

## Notes
- stdout is redirected to stderr.
- a simple cgiLog function is included for debug purpouses.
- tested on linux only.
