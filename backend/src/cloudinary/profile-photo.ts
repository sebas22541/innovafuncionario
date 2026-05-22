import { HttpError } from "../http-error.ts";
import { uploadUserProfilePhoto } from "./upload.ts";

type StoreUserProfilePhotoInput = {
  photoSource: string;
  email: string;
  ci?: string | null;
  userId?: number | null;
};

export async function storeUserProfilePhoto(
  input: StoreUserProfilePhotoInput,
): Promise<string> {
  try {
    return await uploadUserProfilePhoto(input);
  } catch (error) {
    console.error("Error al subir foto de perfil a Cloudinary:", error);
    throw new HttpError(
      500,
      "No fue posible guardar la foto de perfil en Cloudinary.",
    );
  }
}
