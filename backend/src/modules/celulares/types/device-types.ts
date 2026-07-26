export type DeviceHeartbeatInput = {
  deviceId: string;
  platform: string;
  manufacturer: string | null;
  model: string | null;
  androidSdk: number | null;
  batteryLevel: number | null;
  isCharging: boolean | null;
  brightness: number | null;
  kioskEnabled: boolean;
};
