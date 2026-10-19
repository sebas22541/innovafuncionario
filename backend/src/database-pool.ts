import { Pool, type PoolConfig } from "pg";

export function createDatabasePool(config: PoolConfig) {
  return new Pool(config);
}
