import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  PDFDocument,
  appendBezierCurve,
  clip,
  closePath,
  endPath,
  lineTo,
  moveTo,
  popGraphicsState,
  pushGraphicsState,
  rgb,
  StandardFonts,
} from "pdf-lib";
import QRCode from "qrcode";

import { HttpError } from "../http-error.ts";
import { CLOUDINARY } from "./credentials.ts";
import { uploadBufferToCloudinary } from "./upload.ts";

type CredentialUser = {
  id: number;
  email: string;
  nombre_completo?: string | null;
  nombres?: string | null;
  primer_apellido?: string | null;
  segundo_apellido?: string | null;
  tercer_apellido?: string | null;
  ci?: string | null;
  cargo?: string | null;
  unidad?: string | null;
  foto_url?: string | null;
  oficinas?: {
    oficina?: string | null;
  } | null;
  oficina_comision?: {
    oficina?: string | null;
  } | null;
};

type CredentialPerson = {
  codigo_qr?: string | null;
} | null;

export type UserCredentialResult = {
  frontImageUrl: string;
  pdfUrl: string;
  qrPayload: string;
  generatedAt: string;
};

const currentFilePath = fileURLToPath(import.meta.url);
const currentDir = path.dirname(currentFilePath);
const defaultTemplatePaths = [
  path.resolve(currentDir, "../../assets/templates/credencial.pdf"),
  path.resolve(currentDir, "../../../frontend/assets/templates/credencial.pdf"),
];

export async function generateAndStoreUserCredential(
  user: CredentialUser,
  person: CredentialPerson,
): Promise<UserCredentialResult> {
  const cloudName = CLOUDINARY.cloud_name?.trim();

  if (!cloudName) {
    throw new HttpError(500, "Cloudinary no esta configurado.");
  }

  const token = normalizePublicToken(user.ci) ?? `id-${user.id}`;
  const frontPdfImagePublicId = `credencial-frente-pdf-${token}`;
  const frontPdfImageUrl = buildCloudinaryPdfPageImageUrl({
    cloudName,
    folder: "imagenes/credenciales",
    publicId: frontPdfImagePublicId,
  });
  const qrPayload = buildCredentialQrPayload(frontPdfImageUrl, user, person);
  const qrPng = await QRCode.toBuffer(qrPayload, {
    type: "png",
    errorCorrectionLevel: "M",
    margin: 2,
    width: 760,
    color: {
      dark: "#101828",
      light: "#FFFFFF",
    },
  });
  const pdfBytes = await buildCredentialPdf({
    user,
    qrPng,
    qrPayload,
    frontImageUrl: frontPdfImageUrl,
  });

  await uploadBufferToCloudinary({
    buffer: Buffer.from(pdfBytes),
    folder: "imagenes/credenciales",
    publicId: frontPdfImagePublicId,
    resourceType: "image",
    filename: `${frontPdfImagePublicId}.pdf`,
    mimetype: "application/pdf",
  });

  return {
    frontImageUrl: frontPdfImageUrl,
    pdfUrl: frontPdfImageUrl,
    qrPayload,
    generatedAt: new Date().toISOString(),
  };
}

export async function generateUserCredentialPdf(
  user: CredentialUser,
  person: CredentialPerson,
) {
  const cloudName = CLOUDINARY.cloud_name?.trim();

  if (!cloudName) {
    throw new HttpError(500, "Cloudinary no esta configurado.");
  }

  const token = normalizePublicToken(user.ci) ?? `id-${user.id}`;
  const frontPdfImagePublicId = `credencial-frente-pdf-${token}`;
  const frontImageUrl = buildCloudinaryPdfPageImageUrl({
    cloudName,
    folder: "imagenes/credenciales",
    publicId: frontPdfImagePublicId,
  });
  const qrPayload = buildCredentialQrPayload(frontImageUrl, user, person);
  const qrPng = await QRCode.toBuffer(qrPayload, {
    type: "png",
    errorCorrectionLevel: "M",
    margin: 2,
    width: 760,
    color: {
      dark: "#101828",
      light: "#FFFFFF",
    },
  });

  const pdfBytes = await buildCredentialPdf({
    user,
    qrPng,
    qrPayload,
    frontImageUrl,
  });

  await uploadBufferToCloudinary({
    buffer: Buffer.from(pdfBytes),
    folder: "imagenes/credenciales",
    publicId: frontPdfImagePublicId,
    resourceType: "image",
    filename: `${frontPdfImagePublicId}.pdf`,
    mimetype: "application/pdf",
  });

  return pdfBytes;
}

async function buildCredentialPdf(input: {
  user: CredentialUser;
  qrPng: Buffer;
  qrPayload: string;
  frontImageUrl: string;
}) {
  const templateBytes = await readCredentialTemplate();
  const pdf = await PDFDocument.load(templateBytes);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const boldFont = await pdf.embedFont(StandardFonts.HelveticaBold);
  const qrImage = await pdf.embedPng(input.qrPng);
  const photoImage = await resolvePdfPhotoImage(pdf, input.user.foto_url);
  const pages = pdf.getPages();
  const frontPage = pages[0];
  const frontPageSize = frontPage.getSize();
  const backPage = pages[1] ?? pdf.addPage([
    frontPageSize.width,
    frontPageSize.height,
  ]);

  drawFrontPageData(frontPage, {
    user: input.user,
    font,
    boldFont,
    photoImage,
  });
  drawBackPageQr(backPage, {
    qrImage,
    font,
    qrPayload: input.qrPayload,
  });

  pdf.setTitle(`Credencial ${buildDisplayName(input.user)}`);
  pdf.setSubject(input.frontImageUrl);
  pdf.setAuthor("Gobierno Autonomo Municipal de Cochabamba");

  return pdf.save();
}

async function readCredentialTemplate() {
  const configuredPath = process.env.CREDENTIAL_TEMPLATE_PATH?.trim();
  const candidatePaths = configuredPath
    ? [configuredPath, ...defaultTemplatePaths]
    : defaultTemplatePaths;
  const attemptedPaths: string[] = [];

  for (const candidatePath of candidatePaths) {
    attemptedPaths.push(candidatePath);

    try {
      return await readFile(candidatePath);
    } catch (error: any) {
      if (error?.code !== "ENOENT") {
        throw error;
      }
    }
  }

  throw new HttpError(
    500,
    `No se encontro la plantilla de credencial. Rutas revisadas: ${attemptedPaths.join(", ")}`,
  );
}

function drawFrontPageData(page: any, input: {
  user: CredentialUser;
  font: any;
  boldFont: any;
  photoImage: any | null;
}) {
  const { width, height } = page.getSize();
  const ink = rgb(0.08, 0.09, 0.12);
  const blue = rgb(0.00, 0.64, 0.82);
  const photoBorderBlue = rgb(0.00, 0.68, 0.86);
  const muted = rgb(0.13, 0.18, 0.26);
  const textHorizontalMargin = width * 0.045;
  const photoHorizontalMargin = width * 0.06;
  const fieldX = textHorizontalMargin;
  const fieldWidth = width - (textHorizontalMargin * 2);
  const fieldGap = height * 0.052;
  const textBlockRaise = height * 0.035;
  const officeY = (height * 0.145) + textBlockRaise;
  const cargoY = officeY + fieldGap;
  const ciY = cargoY + fieldGap;
  const surnameY = ciY + fieldGap;
  const nameY = surnameY + (height * 0.058);

  if (input.photoImage) {
    const photoRight = width - photoHorizontalMargin;
    const photoFrame = {
      x: width * 0.435,
      y: height * 0.452,
      width: photoRight - (width * 0.435),
      height: height * 0.492,
    };

    drawFramedPhoto(page, input.photoImage, photoFrame, photoBorderBlue);
  }

  drawWrappedText(page, buildGivenNames(input.user), {
    x: fieldX,
    y: nameY,
    maxWidth: fieldWidth,
    size: 13,
    font: input.boldFont,
    color: ink,
    lineGap: 1,
    maxLines: 1,
  });
  drawWrappedText(page, buildLastNames(input.user), {
    x: fieldX,
    y: surnameY,
    maxWidth: fieldWidth,
    size: 13,
    font: input.boldFont,
    color: ink,
    lineGap: 1,
    maxLines: 1,
  });
  drawWrappedText(page, `C.I. ${normalizeText(input.user.ci) || "No registrado"}`, {
    x: fieldX,
    y: ciY,
    maxWidth: fieldWidth,
    size: 7.5,
    font: input.font,
    color: ink,
    lineGap: 1,
    maxLines: 1,
  });
  drawWrappedText(page, normalizeText(input.user.cargo) || "No registrado", {
    x: fieldX,
    y: cargoY,
    maxWidth: fieldWidth,
    size: 8,
    font: input.font,
    color: muted,
    lineGap: 1,
    maxLines: 2,
  });
  drawWrappedText(page, resolveOfficeName(input.user) || "No registrada", {
    x: fieldX,
    y: officeY,
    maxWidth: fieldWidth,
    size: 7.8,
    font: input.font,
    color: blue,
    lineGap: 1.2,
    maxLines: 3,
  });
}

function drawFramedPhoto(
  page: any,
  image: any,
  frame: { x: number; y: number; width: number; height: number },
  borderColor: any,
) {
  const topRightRadius = frame.width * 0.42;
  const bottomLeftRadius = frame.width * 0.30;
  const path = buildPhotoFramePath(frame, topRightRadius, bottomLeftRadius);

  page.pushOperators(
    pushGraphicsState(),
    ...buildPhotoFrameOperators(frame, topRightRadius, bottomLeftRadius),
    clip(),
    endPath(),
  );
  page.drawImage(image, frame);
  page.pushOperators(popGraphicsState());
  page.drawSvgPath(path, {
    borderColor,
    borderWidth: 2.4,
  });
}

function buildPhotoFrameOperators(
  frame: { x: number; y: number; width: number; height: number },
  topRightRadius: number,
  bottomLeftRadius: number,
) {
  const { x, y, width, height } = frame;
  const k = 0.5522847498;
  const right = x + width;
  const top = y + height;

  return [
    moveTo(x + bottomLeftRadius, y),
    lineTo(right, y),
    lineTo(right, top - topRightRadius),
    appendBezierCurve(
      right,
      top - topRightRadius + (topRightRadius * k),
      right - topRightRadius + (topRightRadius * k),
      top,
      right - topRightRadius,
      top,
    ),
    lineTo(x, top),
    lineTo(x, y + bottomLeftRadius),
    appendBezierCurve(
      x,
      y + bottomLeftRadius - (bottomLeftRadius * k),
      x + bottomLeftRadius - (bottomLeftRadius * k),
      y,
      x + bottomLeftRadius,
      y,
    ),
    closePath(),
  ];
}

function buildPhotoFramePath(
  frame: { x: number; y: number; width: number; height: number },
  topRightRadius: number,
  bottomLeftRadius: number,
) {
  const { x, y, width, height } = frame;
  const k = 0.5522847498;
  const right = x + width;
  const top = y + height;

  return [
    `M ${x + bottomLeftRadius} ${y}`,
    `L ${right} ${y}`,
    `L ${right} ${top - topRightRadius}`,
    `C ${right} ${top - topRightRadius + (topRightRadius * k)} ${right - topRightRadius + (topRightRadius * k)} ${top} ${right - topRightRadius} ${top}`,
    `L ${x} ${top}`,
    `L ${x} ${y + bottomLeftRadius}`,
    `C ${x} ${y + bottomLeftRadius - (bottomLeftRadius * k)} ${x + bottomLeftRadius - (bottomLeftRadius * k)} ${y} ${x + bottomLeftRadius} ${y}`,
    "Z",
  ].join(" ");
}

function drawBackPageQr(page: any, input: {
  qrImage: any;
  font: any;
  qrPayload: string;
}) {
  const { width, height } = page.getSize();
  const qrSize = Math.min(width * 0.55, height * 0.36);
  const x = (width - qrSize) / 2;
  const y = height * 0.02;

  page.drawImage(input.qrImage, {
    x,
    y,
    width: qrSize,
    height: qrSize,
  });
}

function drawLabelValue(page: any, value: string, rawText: string | null | undefined, options: {
  x: number;
  y: number;
  maxWidth: number;
  labelFont: any;
  valueFont: any;
  labelColor: any;
  valueColor: any;
}) {
  page.drawText(value.toUpperCase(), {
    x: options.x,
    y: options.y + 18,
    size: 7,
    font: options.labelFont,
    color: options.labelColor,
  });
  drawWrappedText(page, normalizeText(rawText) || "No registrado", {
    x: options.x,
    y: options.y,
    maxWidth: options.maxWidth,
    size: 10,
    font: options.valueFont,
    color: options.valueColor,
    lineGap: 3,
  });
}

function drawWrappedText(page: any, text: string, options: {
  x: number;
  y: number;
  maxWidth: number;
  size: number;
  font: any;
  color: any;
  lineGap: number;
  maxLines?: number;
}) {
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let currentLine = "";

  for (const word of words) {
    const candidate = currentLine.length === 0 ? word : `${currentLine} ${word}`;

    if (options.font.widthOfTextAtSize(candidate, options.size) <= options.maxWidth) {
      currentLine = candidate;
    } else {
      if (currentLine.length > 0) {
        lines.push(currentLine);
      }
      currentLine = word;
    }
  }

  if (currentLine.length > 0) {
    lines.push(currentLine);
  }

  lines.slice(0, options.maxLines ?? 4).forEach((line, index) => {
    page.drawText(line, {
      x: options.x,
      y: options.y - (index * (options.size + options.lineGap)),
      size: options.size,
      font: options.font,
      color: options.color,
    });
  });
}

async function resolvePdfPhotoImage(pdf: PDFDocument, photoUrl?: string | null) {
  const photoBytes = await fetchPhotoBytes(photoUrl);

  if (!photoBytes) {
    return null;
  }

  try {
    return await pdf.embedJpg(photoBytes);
  } catch (_) {
    try {
      return await pdf.embedPng(photoBytes);
    } catch (_) {
      return null;
    }
  }
}

async function resolvePhotoDataUri(photoUrl?: string | null) {
  const photoBytes = await fetchPhotoBytes(photoUrl);

  if (!photoBytes) {
    return null;
  }

  return `data:image/jpeg;base64,${Buffer.from(photoBytes).toString("base64")}`;
}

async function fetchPhotoBytes(photoUrl?: string | null) {
  const normalizedUrl = normalizeText(photoUrl);

  if (!normalizedUrl) {
    return null;
  }

  if (!/^https?:\/\//i.test(normalizedUrl)) {
    try {
      return Buffer.from(normalizedUrl.replace(/^data:[^;]+;base64,/i, ""), "base64");
    } catch (_) {
      return null;
    }
  }

  try {
    const response = await fetch(normalizedUrl);

    if (!response.ok) {
      return null;
    }

    return Buffer.from(await response.arrayBuffer());
  } catch (_) {
    return null;
  }
}

function buildFrontCredentialSvg(input: {
  user: CredentialUser;
  person: CredentialPerson;
  photoDataUri: string | null;
}) {
  const name = escapeXml(buildDisplayName(input.user));
  const ci = escapeXml(normalizeText(input.user.ci) || "No registrado");
  const cargo = escapeXml(normalizeText(input.user.cargo) || "No registrado");
  const oficina = escapeXml(resolveOfficeName(input.user) || "No registrada");
  const code = escapeXml(normalizeText(input.person?.codigo_qr) || `USR-${input.user.id}`);
  const initial = escapeXml(name.trim().charAt(0).toUpperCase() || "U");
  const photo = input.photoDataUri
    ? `<image href="${input.photoDataUri}" x="552" y="142" width="178" height="218" preserveAspectRatio="xMidYMid slice" clip-path="url(#photoClip)"/>`
    : `<rect x="552" y="142" width="178" height="218" rx="22" fill="#F2F4F7"/><text x="641" y="272" text-anchor="middle" font-family="Arial" font-size="72" font-weight="700" fill="#F15A24">${initial}</text>`;

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="860" height="540" viewBox="0 0 860 540">
  <defs>
    <clipPath id="photoClip"><rect x="552" y="142" width="178" height="218" rx="22"/></clipPath>
  </defs>
  <rect width="860" height="540" rx="34" fill="#FFFFFF"/>
  <rect x="0" y="0" width="860" height="108" fill="#F15A24"/>
  <rect x="0" y="108" width="860" height="18" fill="#101828"/>
  <text x="54" y="68" font-family="Arial" font-size="28" font-weight="700" fill="#FFFFFF">Credencial de Funcionario</text>
  <text x="54" y="174" font-family="Arial" font-size="17" font-weight="700" fill="#F15A24">NOMBRE COMPLETO</text>
  <text x="54" y="214" font-family="Arial" font-size="31" font-weight="700" fill="#101828">${name}</text>
  <text x="54" y="284" font-family="Arial" font-size="17" font-weight="700" fill="#F15A24">CI</text>
  <text x="54" y="322" font-family="Arial" font-size="28" fill="#101828">${ci}</text>
  <text x="54" y="386" font-family="Arial" font-size="17" font-weight="700" fill="#F15A24">CARGO</text>
  <text x="54" y="420" font-family="Arial" font-size="22" fill="#344054">${cargo}</text>
  <text x="54" y="472" font-family="Arial" font-size="17" font-weight="700" fill="#F15A24">OFICINA</text>
  <text x="54" y="506" font-family="Arial" font-size="20" fill="#344054">${oficina}</text>
  <rect x="540" y="130" width="202" height="242" rx="28" fill="#FFFFFF" stroke="#D0D5DD" stroke-width="3"/>
  ${photo}
  <text x="641" y="424" text-anchor="middle" font-family="Arial" font-size="15" fill="#667085">ID: ${code}</text>
</svg>`;
}

function buildCloudinaryDeliveryUrl(input: {
  cloudName: string;
  resourceType: "image" | "raw";
  folder: string;
  publicId: string;
  extension: string;
}) {
  const pathParts = [...input.folder.split("/"), input.publicId]
    .map(encodeURIComponent)
    .join("/");

  return `https://res.cloudinary.com/${encodeURIComponent(input.cloudName)}/${input.resourceType}/upload/${pathParts}.${input.extension}`;
}

function buildCloudinaryPdfPageImageUrl(input: {
  cloudName: string;
  folder: string;
  publicId: string;
}) {
  const pathParts = [...input.folder.split("/"), input.publicId]
    .map(encodeURIComponent)
    .join("/");

  return `https://res.cloudinary.com/${encodeURIComponent(input.cloudName)}/image/upload/pg_1,dn_400,w_1200,f_jpg,q_auto:best/${pathParts}.jpg`;
}

function buildCredentialQrPayload(
  frontImageUrl: string,
  user: CredentialUser,
  person: CredentialPerson,
) {
  const codigoQr = normalizeText(person?.codigo_qr) ??
    normalizeText(user.ci) ??
    `USR-${user.id}`;

  return appendCredentialQrCode(frontImageUrl, codigoQr);
}

function appendCredentialQrCode(frontImageUrl: string, codigoQr: string) {
  const separator = frontImageUrl.includes("?") ? "&" : "?";

  return `${frontImageUrl}${separator}codigoQr=${encodeURIComponent(codigoQr)}`;
}

function stripVersionFromCloudinaryUrl(url: string) {
  return url.replace(/\/v\d+\//, "/");
}

function buildDisplayName(user: CredentialUser) {
  return [
    user.nombres,
    user.primer_apellido,
    user.segundo_apellido,
    user.tercer_apellido,
  ]
    .map((value) => normalizeText(value))
    .filter((value): value is string => Boolean(value))
    .join(" ") || normalizeText(user.nombre_completo) || "Usuario";
}

function buildGivenNames(user: CredentialUser) {
  return normalizeText(user.nombres) ??
    splitFallbackName(user.nombre_completo).givenNames ??
    "Usuario";
}

function buildLastNames(user: CredentialUser) {
  return [
    user.primer_apellido,
    user.segundo_apellido,
    user.tercer_apellido,
  ]
    .map((value) => normalizeText(value))
    .filter((value): value is string => Boolean(value))
    .join(" ") || splitFallbackName(user.nombre_completo).lastNames || "";
}

function splitFallbackName(value: string | null | undefined) {
  const parts = normalizeText(value)?.split(/\s+/).filter(Boolean) ?? [];

  if (parts.length <= 1) {
    return {
      givenNames: parts[0] ?? null,
      lastNames: null,
    };
  }

  return {
    givenNames: parts.slice(0, Math.max(1, parts.length - 2)).join(" "),
    lastNames: parts.slice(Math.max(1, parts.length - 2)).join(" "),
  };
}

function resolveOfficeName(user: CredentialUser) {
  return normalizeText(user.oficinas?.oficina) ?? normalizeText(user.unidad);
}

function normalizePublicToken(value: string | null | undefined) {
  const normalizedValue = normalizeText(value)?.toLowerCase();

  if (!normalizedValue) {
    return null;
  }

  return normalizedValue
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function normalizeText(value: string | null | undefined) {
  const normalized = value?.trim() ?? "";
  return normalized.length === 0 ? null : normalized;
}

function escapeXml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
