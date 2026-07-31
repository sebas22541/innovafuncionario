export default function handler(_request: any, response: any) {
  response.writeHead(200, {
    "Content-Type": "application/json; charset=utf-8",
  });
  response.end(JSON.stringify({ status: "ok", service: "api" }));
}
