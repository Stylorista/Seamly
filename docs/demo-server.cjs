const http = require('http');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const outputPath = path.join(root, 'downloads', 'Seamly-camera-AI-demo.webm');
const latestOutputPath = path.join(root, 'downloads', 'Seamly-camera-AI-demo-latest.webm');
const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};

function safePath(urlPath) {
  const requested = decodeURIComponent(urlPath.split('?')[0]);
  const relative = requested === '/' ? 'docs/seamly-camera-demo.html' : requested.replace(/^\/+/, '');
  const candidate = path.resolve(root, relative);
  return candidate.startsWith(root + path.sep) ? candidate : null;
}

const server = http.createServer((request, response) => {
  if (request.method === 'POST' && request.url === '/save-latest-demo') {
    const chunks = [];
    request.on('data', (chunk) => chunks.push(chunk));
    request.on('end', () => {
      const video = Buffer.concat(chunks);
      fs.writeFile(latestOutputPath, video, (error) => {
        if (error) {
          response.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
          response.end('Could not save latest demo video.');
          return;
        }
        response.writeHead(201, { 'Content-Type': 'application/json; charset=utf-8' });
        response.end(JSON.stringify({ path: latestOutputPath, bytes: video.length }));
      });
    });
    return;
  }

  if (request.method === 'POST' && request.url === '/save-demo') {
    const chunks = [];
    request.on('data', (chunk) => chunks.push(chunk));
    request.on('end', () => {
      const video = Buffer.concat(chunks);
      fs.writeFile(outputPath, video, (error) => {
        if (error) {
          response.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
          response.end('Could not save demo video.');
          return;
        }
        response.writeHead(201, { 'Content-Type': 'application/json; charset=utf-8' });
        response.end(JSON.stringify({ path: outputPath, bytes: video.length }));
      });
    });
    return;
  }

  if (request.method !== 'GET') {
    response.writeHead(405);
    response.end('Method not allowed');
    return;
  }
  const filePath = safePath(request.url);
  if (!filePath) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }
  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }
    const type = contentTypes[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
    response.writeHead(200, { 'Content-Type': type });
    response.end(data);
  });
});

server.listen(8787, '127.0.0.1', () => {
  console.log('Seamly demo server listening on http://127.0.0.1:8787');
});
