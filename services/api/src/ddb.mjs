// DynamoDB data layer — single-table, always scoped to one user's partition
// (PK = USER#<sub>). Callers never pass a partition key, so there is no path to
// another user's data. Optimistic concurrency via a numeric `version` attribute.
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand, GetCommand, PutCommand, DeleteCommand, BatchWriteCommand } from '@aws-sdk/lib-dynamodb';
import { VersionConflict } from './errors.mjs';

export { VersionConflict };

export function createDynamoData({ tableName, client } = {}) {
  const table = tableName || process.env.TABLE_NAME;
  const doc = DynamoDBDocumentClient.from(client || new DynamoDBClient({}), {
    marshallOptions: { removeUndefinedValues: true },
  });
  const pk = (sub) => `USER#${sub}`;

  return {
    async queryUser(sub) {
      const res = await doc.send(new QueryCommand({
        TableName: table,
        KeyConditionExpression: 'PK = :pk',
        ExpressionAttributeValues: { ':pk': pk(sub) },
      }));
      return (res.Items || []).map(stripKeys);
    },

    async getItem(sub, sk) {
      const res = await doc.send(new GetCommand({ TableName: table, Key: { PK: pk(sub), SK: sk } }));
      return res.Item ? stripKeys(res.Item) : null;
    },

    // Upsert with optional optimistic concurrency. expectedVersion:
    //   undefined -> unconditional; number -> only if current version matches.
    async putItem(sub, sk, attrs, { expectedVersion } = {}) {
      const nextVersion = (typeof expectedVersion === 'number' ? expectedVersion : (attrs.version || 0)) + 1;
      const item = { ...attrs, PK: pk(sub), SK: sk, version: nextVersion, updatedAt: new Date().toISOString() };
      const cmd = { TableName: table, Item: item };
      if (typeof expectedVersion === 'number') {
        cmd.ConditionExpression = 'attribute_not_exists(version) OR version = :ev';
        cmd.ExpressionAttributeValues = { ':ev': expectedVersion };
      }
      try {
        await doc.send(new PutCommand(cmd));
      } catch (err) {
        if (err && err.name === 'ConditionalCheckFailedException') throw new VersionConflict();
        throw err;
      }
      return stripKeys(item);
    },

    async deleteItem(sub, sk) {
      await doc.send(new DeleteCommand({ TableName: table, Key: { PK: pk(sub), SK: sk } }));
      return true;
    },

    // Bulk upsert for one-time imports. records: [{ sk, attrs }]. Overwrites
    // each item (owner-scoped), stamping version + updatedAt. Batches of 25 with
    // a retry for UnprocessedItems. Returns the number of records written.
    async bulkPut(sub, records) {
      const now = new Date().toISOString();
      const items = records
        .filter((r) => r && r.sk && r.attrs && typeof r.attrs === 'object')
        .map(({ sk, attrs }) => ({ ...attrs, PK: pk(sub), SK: sk, version: 1, updatedAt: now }));
      for (let i = 0; i < items.length; i += 25) {
        let request = { [table]: items.slice(i, i + 25).map((Item) => ({ PutRequest: { Item } })) };
        for (let attempt = 0; attempt < 6; attempt++) {
          const res = await doc.send(new BatchWriteCommand({ RequestItems: request }));
          const un = res.UnprocessedItems && res.UnprocessedItems[table];
          if (!un || un.length === 0) break;
          request = { [table]: un };
          await new Promise((r) => setTimeout(r, 150 * (attempt + 1))); // backoff
        }
      }
      return items.length;
    },
  };
}

// Hide the physical keys from API responses.
function stripKeys(item) {
  const { PK, SK, GSI1PK, GSI1SK, ...rest } = item; // eslint-disable-line no-unused-vars
  return rest;
}
