import type { UploadApiOptions } from "cloudinary";

export interface ParamUploadClaudinary extends UploadApiOptions {
  file: Express.Multer.File;
}
