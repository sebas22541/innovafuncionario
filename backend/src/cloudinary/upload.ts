import { claudinaryConfig, cloudinary } from "./config.ts";
import type { ParamUploadClaudinary } from "./types/paramUpload.ts";
import type { ResponseUploadClaudinary } from "./types/responseUpload.ts";

type UploadUserProfilePhotoInput = {
  photoSource: string;
  email: string;
  ci?: string | null;
  userId?: number | null;
};

type UploadBufferInput = {
  buffer: Buffer;
  folder: string;
  publicId: string;
  resourceType: "image" | "raw" | "auto";
  filename: string;
  mimetype: string;
};

export const uploadClaudinary = async (
  dto: ParamUploadClaudinary,
): Promise<ResponseUploadClaudinary> => {
  const { file, ...options } = dto;

  if (!file) {
    throw new Error("No se envio ningun archivo");
  }

  claudinaryConfig();

  return new Promise((resolve, reject) => {
    const uploadStream = cloudinary.uploader.upload_stream(
      {
        resource_type: "auto",
        folder: "imagenes/usuarios",
        ...options,
      },
      (error, result) => {
        if (error) {
          reject(error);
          return;
        }

        if (!result) {
          reject(new Error("Error al subir a Cloudinary"));
          return;
        }

        resolve(result as ResponseUploadClaudinary);
      },
    );

    uploadStream.end(file.buffer);
  });
};

export const uploadUserProfilePhoto = async ({
  photoSource,
  email,
  ci,
  userId,
}: UploadUserProfilePhotoInput): Promise<string> => {
  const normalizedSource = photoSource.trim();

  if (normalizedSource.length === 0) {
    throw new Error("No se envio ningun archivo");
  }

  if (looksLikeRemoteUrl(normalizedSource)) {
    return normalizedSource;
  }

  const { buffer, mimeType, extension } = decodeProfilePhoto(normalizedSource);
  const publicId = buildUserProfilePhotoPublicId({
    email,
    ci,
    userId,
  });

  const uploadResult = await uploadClaudinary({
    file: {
      buffer,
      size: buffer.length,
      mimetype: mimeType,
      originalname: `${publicId}.${extension}`,
    } as Express.Multer.File,
    folder: "imagenes/usuarios",
    public_id: publicId,
    overwrite: true,
    invalidate: true,
    resource_type: "image",
    use_filename: false,
    unique_filename: false,
  });

  return uploadResult.secure_url;
};

export const uploadBufferToCloudinary = async ({
  buffer,
  folder,
  publicId,
  resourceType,
  filename,
  mimetype,
}: UploadBufferInput): Promise<string> => {
  const uploadResult = await uploadClaudinary({
    file: {
      buffer,
      size: buffer.length,
      mimetype,
      originalname: filename,
    } as Express.Multer.File,
    folder,
    public_id: publicId,
    overwrite: true,
    invalidate: true,
    resource_type: resourceType,
    use_filename: false,
    unique_filename: false,
  });

  return uploadResult.secure_url;
};

function decodeProfilePhoto(photoSource: string) {
  const dataUriMatch = photoSource.match(/^data:(image\/[a-z0-9.+-]+);base64,(.+)$/i);
  const encodedPayload = dataUriMatch?.[2] ?? photoSource;
  const buffer = Buffer.from(encodedPayload, "base64");

  if (buffer.length === 0) {
    throw new Error("La foto de perfil no contiene datos validos.");
  }

  const mimeType = dataUriMatch?.[1]?.toLowerCase() ?? inferImageMimeType(buffer);
  return {
    buffer,
    mimeType,
    extension: mimeTypeToExtension(mimeType),
  };
}

function inferImageMimeType(buffer: Buffer): string {
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return "image/png";
  }

  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8) {
    return "image/jpeg";
  }

  if (
    buffer.length >= 6 &&
    buffer.subarray(0, 3).toString("ascii") === "GIF"
  ) {
    return "image/gif";
  }

  if (
    buffer.length >= 12 &&
    buffer.subarray(0, 4).toString("ascii") === "RIFF" &&
    buffer.subarray(8, 12).toString("ascii") === "WEBP"
  ) {
    return "image/webp";
  }

  return "image/jpeg";
}

function mimeTypeToExtension(mimeType: string): string {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/gif":
      return "gif";
    case "image/webp":
      return "webp";
    case "image/jpeg":
    default:
      return "jpg";
  }
}

function buildUserProfilePhotoPublicId(input: {
  email: string;
  ci?: string | null;
  userId?: number | null;
}): string {
  const primaryToken = input.userId != null
    ? `id-${input.userId}`
    : normalizePublicIdToken(input.ci) ??
      normalizePublicIdToken(input.email) ??
      "usuario";

  return `perfil-${primaryToken}`;
}

function normalizePublicIdToken(value: string | null | undefined): string | null {
  const normalizedValue = value?.trim().toLowerCase() ?? "";

  if (normalizedValue.length === 0) {
    return null;
  }

  return normalizedValue
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function looksLikeRemoteUrl(value: string): boolean {
  try {
    const parsedValue = new URL(value);
    return parsedValue.protocol === "http:" || parsedValue.protocol === "https:";
  } catch (_) {
    return false;
  }
}
