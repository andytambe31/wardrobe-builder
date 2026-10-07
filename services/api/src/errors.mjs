// Shared error types with no runtime dependencies, so modules that need to
// reference them (handlers, tests) don't transitively pull in the AWS SDK.

export class VersionConflict extends Error {
  constructor() {
    super('version conflict');
    this.name = 'VersionConflict';
    this.code = 'version_conflict';
  }
}
