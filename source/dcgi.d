/+
MIT License

Copyright (c) 2020 2night SpA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
+/

module dcgi;

/// UDA for your handler
struct MaxRequestBodyLength { size_t length; }

///
enum DisplayExceptions;

/// Remember to mixin this template inside your main file.
template DCGI(alias handler = null)
{
   void main()
   {
      static if (is(typeof(handler) == typeof(null)))
      {
         static if (!__traits(compiles, cgi(Request.init, Output.init))) static assert(0, "You must define: void cgi(Request r, Output o) { ... }");
         else cgiMain!cgi();  
      }
      else 
      {
         static if (!__traits(compiles, handler(Request.init, Output.init))) static assert(0, "You must define: void " ~ handler.stringof ~ "(Request r, Output o) { ... }");
         else cgiMain!handler();  
      }   
   }
}

/// You're supposed not to call this function. It is called from the mixed-in code
void cgiMain(alias handler)()
{
   import std.traits : hasUDA, getUDAs;
   import std.file : readText;

   // Redirecting stdout to avoid mistakes using writeln & c.
   import std.stdio : stdout, stderr;
   auto stream = stdout;
   stdout = stderr;

   import std.format : format;
   import std.conv : to;
   import std.process : environment;
   import std.string : toUpper;
   import std.algorithm : map;
   import std.array : assocArray;
   import std.typecons : tuple;

   string[string] headers = 
      environment
      .toAA
      .byKeyValue
      .map!(t => tuple(t.key.toUpper,t.value))
      .assocArray;

   char[] buffer;

   Request  request;
   Output   output;
   bool     showExceptions;
   size_t   maxRequestBodyLength = 1024*4;

   try { 
      output = new Output(stream);
      showExceptions = hasUDA!(handler, DisplayExceptions);

      static if (hasUDA!(handler, MaxRequestBodyLength))
         maxRequestBodyLength = getUDAs!(handler, MaxRequestBodyLength)[0].length;
      
      {
         // Read body data
         import std.stdio : stdin;
         import core.sys.posix.sys.select;

         // Is there anything on stdin?
         timeval tv = timeval(0, 1);
         fd_set fds;
         FD_ZERO(&fds);
         FD_SET(0, &fds);
         select(0+1, &fds, null, null, &tv);
         
         bool hasData = FD_ISSET(0, &fds);
         if (hasData)
         {
            buffer.length = maxRequestBodyLength + 1;
            auto requestData = stdin.rawRead(buffer);

            if (requestData.length > maxRequestBodyLength) 
               throw new Exception("Request body too large");
            
            buffer.length = requestData.length;
         }
      }

      // Init request. Call handler
      request = new Request(headers, buffer);
      handler(request, output); 
   }
   
   // Unhandled Exception escape from user code
   catch (Exception e) 
   { 
      if (!output.headersSent) 
         output.status = 501; 
      
      cgiLog(format("Unhandled exception: %s", e.msg)); 
      cgiLog(e.to!string);

      if (showExceptions) 
         output(format("<pre>\n%s\n</pre>", e.to!string));
   }

   // Even worst.
   catch (Throwable t) 
   { 
      // I know I'm not supposed to catch Throwable and continue with execution
      // but it just tries to write exception and exit. 

      if (!output.headersSent) 
         output.status = 501; 
         
      cgiLog(format("Throwable: %s", t.msg)); 
      cgiLog(t.to!string);

      if (showExceptions) 
         output(format("<pre>\n%s\n</pre>", t.to!string));
   }

   // No reply so far?
   if (!output.headersSent)
   {
      // Send and empty response
      output("");
   }
}

/// Write a formatted log
void cgiLog(T...)(T params)
{
   import std.datetime : SysTime, Clock;
   import std.conv : to;
   import std.stdio : write, writeln, stderr;

   SysTime t = Clock.currTime;

   stderr.writef(
      "%04d/%02d/%02d %02d:%02d:%02d.%s >>> ", 
      t.year, t.month, t.day, t.hour,t.minute,t.second,t.fracSecs.split!"msecs".msecs
   );

   foreach(p; params)
      stderr.write(p.to!string, " ");

   stderr.writeln;
   stderr.flush;
}

/// A cookie
private import std.datetime : DateTime;
struct Cookie
{
   string      name;       /// Cookie data
   string      value;      /// ditto
   string      path;       /// ditto
   string      domain;     /// ditto

   DateTime    expire;     /// ditto

   bool        session     = true;  /// ditto  
   bool        secure      = false; /// ditto
   bool        httpOnly    = false; /// ditto

   /// Invalidate cookie
   public void invalidate()
   {
      expire = DateTime(1970,1,1,0,0,0);
   }
}

/// A request from user
class Request 
{ 

   /// HTTP methods
   public enum Method
   {
      Get, ///
      Post, ///
      Head, ///
      Delete, ///
      Put, ///
      Unknown = -1 ///
   }
   
   @disable this();

   private this(string[string] headers, char[] requestData) 
   {
      import std.regex : match, ctRegex;
      import std.uri : decodeComponent;
      import std.string : translate, split, toLower;

      // Reset values
      _header  = headers;
      _get 	   = (typeof(_get)).init;
      _post 	= (typeof(_post)).init;
      _cookie  = (typeof(_cookie)).init;
      _data 	= requestData;

      // Read get params
      if ("QUERY_STRING" in _header)
         foreach(m; match(_header["QUERY_STRING"], ctRegex!("([^=&]+)(?:=([^&]+))?&?", "g")))
            _get[m.captures[1].decodeComponent] = translate(m.captures[2], ['+' : ' ']).decodeComponent;

      // Read post params
      if ("REQUEST_METHOD" in _header && _header["REQUEST_METHOD"] == "POST")
         if(_data.length > 0 && split(_header["CONTENT_TYPE"].toLower(),";")[0] == "application/x-www-form-urlencoded")
            foreach(m; match(_data, ctRegex!("([^=&]+)(?:=([^&]+))?&?", "g")))
               _post[m.captures[1].decodeComponent] = translate(m.captures[2], ['+' : ' ']).decodeComponent;

      // Read cookies
      if ("HTTP_COOKIE" in _header)
         foreach(m; match(_header["HTTP_COOKIE"], ctRegex!("([^=]+)=([^;]+);? ?", "g")))
            _cookie[m.captures[1].decodeComponent] = m.captures[2].decodeComponent;

   }

   ///
   @nogc @property nothrow public const(char[]) data() const  { return _data; } 
   
   ///
   @nogc @property nothrow public const(string[string]) get() const { return _get; }
   
   ///
   @nogc @property nothrow public const(string[string]) post()  const { return _post; }
   
   ///
   @nogc @property nothrow public const(string[string]) header() const { return _header; } 
   
   ///
   @nogc @property nothrow public const(string[string]) cookie() const { return _cookie; }  
   
   ///
   @property public Method method() const
   {
      import std.string : toLower;
      switch(_header["REQUEST_METHOD"].toLower())
      {
         case "get": return Method.Get;
         case "post": return Method.Post;
         case "head": return Method.Head;
         case "put": return Method.Put;
         case "delete": return Method.Delete;
         default: return Method.Unknown;  
      }      
   }

   private char[] _data;
   private string[string]  _get;
   private string[string]  _post;
   private string[string]  _header;
   private string[string]  _cookie;
   
}

/// Your reply.
class Output
{
   private import std.stdio : File;

   private struct KeyValue
   {
      this (in string key, in string value) { this.key = key; this.value = value; }
      string key;
      string value;
   }
   
   /// You can add a http header. But you can't if body is already sent.
   public void addHeader(in string key, in string value) 
   {
      if (_headersSent) 
         throw new Exception("Can't add/edit headers. Too late. Just sent.");

      _headers ~= KeyValue(key, value); 
   }

   @disable this();

   private this(File stream)
   {
      _stream = stream;
   }

   /// Force sending of headers.
   public void sendHeaders()
   {
      import std.format : format;

      if (_headersSent) 
         throw new Exception("Can't resend headers. Too late. Just sent.");

      import std.uri : encode;
      
      bool has_content_type = false;
      _stream.write(format("Status: %s\r\n", _status));

      // send user-defined headers
      foreach(header; _headers)
      {
         import std.string : toLower;
         _stream.write(format("%s: %s\r\n", header.key, header.value));
         if (header.key.toLower() == "content-type") has_content_type = true;
      }

      // Default content-type is text/html if not defined by user
      if (!has_content_type)
         _stream.write(format("Content-Type: text/html; charset=utf-8\r\n"));
      
      // If required, I add headers to write cookies
      foreach(Cookie c; _cookies)
      {

         _stream.write(format("Set-Cookie: %s=%s", c.name.encode(), c.value.encode()));
   
         if (!c.session)
         {
            string[] mm = ["", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
            string[] dd = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

            string data = format("%s, %s %s %s %s:%s:%s GMT",
               dd[c.expire.dayOfWeek], c.expire.day, mm[c.expire.month], c.expire.year, 
               c.expire.hour, c.expire.minute, c.expire.second
            );

            _stream.write(format("; Expires=%s", data));
         }

         if (!c.path.length == 0) _stream.write(format("; path=%s", c.path));
         if (!c.domain.length == 0) _stream.write(format("; domain=%s", c.domain));

         if (c.secure) _stream.write(format("; Secure"));
         if (c.httpOnly) _stream.write(format("; HttpOnly"));

         _stream.write("\r\n");
      }
   
      _stream.write("\r\n");
      _headersSent = true;
   }
   
   /// You can set a cookie.  But you can't if body is already sent.
   public void setCookie(Cookie c)
   {
      if (_headersSent) 
         throw new Exception("Can't set cookies. Too late. Just sent.");
      
      _cookies ~= c;
   }
   
   /// Retrieve all cookies
   @nogc @property nothrow public Cookie[]  cookies() 				{ return _cookies; }
   
   /// Output status
   @nogc @property nothrow public ulong 		status() 				{ return _status; }
   
   /// Set response status. Default is 200 (OK)
   @property public void 		               status(ulong status) 
   {
      if (_headersSent) 
         throw new Exception("Can't set status. Too late. Just sent.");

      _status = status; 
   }

   /**
   * Syntax sugar to write data
   * Example:
   * --------------------
   * output("Hello world", "!");
   * --------------------
   */ 
   public void opCall(T...)(T params)
   { 
      import std.conv : to; 
      
      foreach(p; params)
         write(p); 
   }

   /// Write data
   public void write(string data) { import std.string : representation; write(data.representation); }
   
   /// Ditto
   public void write(in void[] data) 
   {
      import std.stdio : stdout;

      if (!_headersSent) 
         sendHeaders(); 
      
      _stream.rawWrite(data); 
   }
   
   /// Are headers already sent?
   @nogc nothrow public bool headersSent() { return _headersSent; }

   private bool			   _headersSent = false;
   private Cookie[]      	_cookies;
   private KeyValue[]  	   _headers;
   private ulong           _status = 200;
   private File            _stream;   
}	