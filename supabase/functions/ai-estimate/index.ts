import { createHandler } from "./service.ts";

Deno.serve(createHandler({ env: (name) => Deno.env.get(name) }));
