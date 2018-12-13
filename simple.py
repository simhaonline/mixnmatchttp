#!/usr/bin/env python3
import socketserver
import http.server, http.server
import ssl
import re
import argparse

AUTH_COOKIE = 'auth=1'

class ThreadingCORSHttpsServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    pass

class CORSHttpsServer(http.server.SimpleHTTPRequestHandler):
    def send_custom_headers(self):
        pass
    
    def show(self):
        print("\n----- Request Start ----->\n")
        print(self.requestline)
        print(self.headers)
        try:
            length = int(self.headers.get('Content-Length'))
        except TypeError:
            pass
        else:
            print(self.rfile.read(length).decode('utf-8'))
        print("<----- Request End -----\n")
    
    def do_OPTIONS(self):
        self.do_HEAD()
    
    def do_HEAD(self):
        self.show()
        super().do_HEAD()
    
    def do_GET(self):
        self.show()
        #  if self.path == '/login':
        #      self.send_response(301)
        #      self.send_header('Location', '/index.html')
        #      self.send_header('Content-type', 'text/html')
        #      self.send_header('Content-Length', '0')
        #      self.send_header('Set-Cookie', AUTH_COOKIE)
        #      self.end_headers()
        if self.headers.get('Cookie') == AUTH_COOKIE or self.path != '/secret.txt':
            super().do_GET()
        else:
            super().send_error(401)
    
    def do_POST(self):
        self.do_GET()
    
    def end_headers(self):
        self.send_custom_headers()
        super().end_headers()

def new_server(clsname, origins, creds, headers):
    def send_custom_headers(self):
        # Disable Cache
        if not re.search('/jquery-[0-9\.]+(\.min)?\.js$', self.path):
            self.send_header('Cache-Control',
                'no-cache, no-store, must-revalidate')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
        
        for h in headers:
            self.send_header(*re.split(': *', h, maxsplit=1))
        
        # CORS
        if origins:
            allowed_origins = origins
            if allowed_origins == '%%ECHO%%':
                allowed_origins = self.headers.get('Origin')
                if not allowed_origins: allowed_origins = '*'
            self.send_header('Access-Control-Allow-Origin',
                allowed_origins)
            if creds:
                self.send_header('Access-Control-Allow-Credentials',
                    'true')
    
    return type(clsname, (CORSHttpsServer,), {
        'send_custom_headers': send_custom_headers})

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
            formatter_class=argparse.ArgumentDefaultsHelpFormatter,
            description='''Serve the current working directory over
            HTTPS and with custom headers.''')
    parser.add_argument('-a', '--address', dest='address',
            default='0.0.0.0', metavar='IP',
            help='''Address of interface to bind to.''')
    parser.add_argument('-p', '--port', dest='port',
            default='58081', metavar='PORT', type=int,
            help='''HTTP port to listen on.''')
    ac_origin_parser = parser.add_mutually_exclusive_group()
    ac_origin_parser.add_argument('-o', '--origins', dest='origins',
            metavar='"Allowed origins"',
            help='''"*" or a coma-separated whitelist of origins.''')
    ac_origin_parser.add_argument('-O', '--all-origins', dest='origins',
            action='store_const', const='%%ECHO%%',
            help='''Allow all origins, i.e. echo the Origin in the
            request.''')
    parser.add_argument('-c', '--cors-credentials', dest='creds',
            default=False, action='store_true',
            help='''Allow sending credentials with CORS requests,
            i.e. add Access-Control-Allow-Credentials. Using this only
            makes sense if you are providing some list of origins (see
            -o and -O options), otherwise this option is ignored.''')
    parser.add_argument('-H', '--headers', dest='headers',
            default=[], metavar='Header: Value', nargs='*',
            help='''Additional headers.''')
    parser.add_argument('-C', '--cert', dest='certfile',
            default='./cert.pem', metavar='FILE',
            help='''PEM file containing the server certificate.''')
    parser.add_argument('-K', '--key', dest='keyfile',
            default='./key.pem', metavar='FILE',
            help='''PEM file containing the private key for the server
            certificate.''')
    parser.add_argument('-S', '--no-ssl', dest='ssl',
            default=True, action='store_false',
            help='''Don't use SSL.''')
    args = parser.parse_args()
    
    httpd = ThreadingCORSHttpsServer((args.address, args.port),
            new_server('CORSHttpsServer',
                args.origins,
                args.creds,
                args.headers))
    if args.ssl:
        httpd.socket = ssl.wrap_socket(
                httpd.socket,
                keyfile=args.keyfile,
                certfile=args.certfile,
                server_side=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.socket.close()
