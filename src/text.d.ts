// keys.txt is bundled into the Worker as a text module via the wrangler "Text"
// rule; declare it so TypeScript treats the import as a string. Same shim as
// resume/src/html.d.ts.
declare module "*.txt" {
  const content: string;
  export default content;
}
