// ESM customization hooks that stub every `@aws-sdk/*` import so the real Lambda
// handlers (router/index.mjs, ws/index.mjs) can be imported and driven in tests
// without the AWS SDK installed. The stub returns command objects whose
// constructor name + input are inspected by a fake DynamoDB the test installs on
// globalThis.__ddb. Registered via node:module `register()` in the test files.
export async function resolve(specifier, context, next) {
  if (specifier.startsWith('@aws-sdk/')) {
    return { url: 'stub:' + specifier, shortCircuit: true };
  }
  return next(specifier, context);
}

export async function load(url, context, next) {
  if (url.startsWith('stub:')) {
    const source = `
      class Cmd { constructor(i){ this.input = i; } }
      export class DynamoDBClient { constructor(){} }
      export class S3Client { send(){ return Promise.resolve({}); } }
      // Delegate to globalThis.__ddb at call time (not at .from() time) so each
      // test can install its own fake AFTER the handler module is imported.
      export class DynamoDBDocumentClient { static from(){ return { send: (cmd) => globalThis.__ddb.send(cmd) }; } }
      export class GetCommand extends Cmd {}
      export class PutCommand extends Cmd {}
      export class DeleteCommand extends Cmd {}
      export class QueryCommand extends Cmd {}
      export class ScanCommand extends Cmd {}
      export class DeleteObjectCommand extends Cmd {}
      export class PutObjectCommand extends Cmd {}
      export class GetObjectCommand extends Cmd {}
      export function getSignedUrl(){ return Promise.resolve('https://signed.example/url'); }
    `;
    return { format: 'module', source, shortCircuit: true };
  }
  return next(url, context);
}
