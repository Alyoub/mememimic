#!/bin/bash
# Double-click to play Meme Mimic on this Mac. It starts a small local web server for this
# folder (the same files as mememimic.com) and opens the game in your browser.
# Close this window to stop it.
cd "$(dirname "$0")" || exit 1
exec python3 - <<'EOF'
import http.server, socket, webbrowser

class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 128   # the game loads many files at once
    daemon_threads = True

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.glb': 'model/gltf-binary', '.m4a': 'audio/mp4', '.js': 'text/javascript',
                      '.webmanifest': 'application/manifest+json'}
    def log_message(self, *args):
        pass

for port in range(8080, 8100):
    try:
        server = Server(('127.0.0.1', port), Handler)
        break
    except OSError:
        continue

url = f'http://127.0.0.1:{port}/'
print(f'\n  Meme Mimic is running at {url}\n  Close this window to stop it.\n', flush=True)
webbrowser.open(url)
server.serve_forever()
EOF
