export default function handler(_request: any, response: any) {
  response.status(404).json({
    error: "Usa las rutas /api, por ejemplo /api/health.",
  });
}
