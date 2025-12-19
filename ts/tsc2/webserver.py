from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse
import json
import logging

# Configure logging to console and file
logging.basicConfig(
    filename='server.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class MyHandler(BaseHTTPRequestHandler):
    def log_request_details(self, method, body=None):
        logging.info(f"{method} request from {self.client_address}")
        logging.info(f"Path: {self.path}")
        logging.info(f"Headers:\n{self.headers}")
        if body:
            logging.info(f"Body:\n{body}")

    def do_GET(self):
        self.log_request_details("GET")
        self.send_response(200)
        self.send_header("Content-type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"<html><body><h1>jurassic park+uh uh uh</h1></body></html>")

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        self.log_request_details("POST", post_data)

        try:
            parsed_data = json.loads(post_data)
        except json.JSONDecodeError:
            parsed_data = urllib.parse.parse_qs(post_data)

        self.send_response(200)
        self.send_header("Content-type", "application/json; charset=utf-8")
        self.end_headers()
        response = {
            "status": "success",
            "received": parsed_data
        }
        self.wfile.write(json.dumps(response).encode('utf-8'))

def run(server_class=HTTPServer, handler_class=MyHandler, port=8080):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"Starting HTTP server on port {port}...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server.")
        httpd.server_close()

if __name__ == "__main__":
    run()
