import { v2 as cloudinary } from "cloudinary";

import { CLOUDINARY } from "./credentials.ts";

let isCloudinaryConfigured = false;

export const claudinaryConfig = () => {
  if (
    !CLOUDINARY.cloud_name ||
    !CLOUDINARY.api_key ||
    !CLOUDINARY.api_secret
  ) {
    throw new Error("ERROR EN LA CONFIGURACION DE CLOUDINARY");
  }

  if (isCloudinaryConfigured) {
    return cloudinary;
  }

  cloudinary.config({
    cloud_name: CLOUDINARY.cloud_name,
    api_key: CLOUDINARY.api_key,
    api_secret: CLOUDINARY.api_secret,
  });

  isCloudinaryConfigured = true;
  console.log("CLOUDINARY CONFIGURADO CORRECTAMENTE");
  return cloudinary;
};

export { cloudinary };
