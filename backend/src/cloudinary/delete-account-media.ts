import { claudinaryConfig } from "./config.ts";
import { CLOUDINARY } from "./credentials.ts";

const token = (value: string) => value.trim().toLowerCase()
  .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80);

export async function deleteAccountMedia(user: {
  id: number; ci: string | null; email: string; foto_url: string | null;
}) {
  // Sin configuracion no se han podido generar archivos de credenciales.
  if (!CLOUDINARY.cloud_name && !user.foto_url) return;
  const cloudinary = claudinaryConfig();
  const ids = new Set<string>();
  if (user.foto_url) {
    const url = new URL(user.foto_url);
    const prefix = `/${CLOUDINARY.cloud_name}/image/upload/`;
    if (url.hostname === "res.cloudinary.com" && url.pathname.startsWith(prefix)) {
      const publicId = decodeURIComponent(url.pathname.slice(prefix.length))
        .replace(/^v\d+\//, "").replace(/\.[^/.]+$/, "");
      if (publicId.startsWith("imagenes/usuarios/")) ids.add(publicId);
    }
  }
  // Incluye las versiones anteriores de la foto, antes y despues de editarla.
  ids.add(`imagenes/usuarios/perfil-id-${user.id}`);
  ids.add(`imagenes/usuarios/perfil-${token(user.ci || user.email)}`);
  ids.add(`imagenes/credenciales/credencial-frente-pdf-${user.ci ? token(user.ci) : `id-${user.id}`}`);
  for (const publicId of ids) {
    const result = await cloudinary.uploader.destroy(publicId, { resource_type: "image", invalidate: true });
    if (result.result !== "ok" && result.result !== "not found") {
      throw new Error("No fue posible eliminar los archivos de la cuenta. Intenta nuevamente.");
    }
  }
}
