import Ajv2020, { type ErrorObject } from "ajv/dist/2020.js";
import schema from "../../schema/manifest-1.json" with { type: "json" };

const ajv = new Ajv2020({ allErrors: true, strict: true });
const validate = ajv.compile(schema);

/**
 * JSON Pointers of every schema error, using the corpus convention: an error points at the offending
 * field, and a missing or unknown field points at where that field is or would be.
 */
export function schemaErrorPointers(manifest: unknown): string[] {
    if (validate(manifest)) return [];
    return [...new Set((validate.errors ?? []).map(pointerOf))].sort();
}

function pointerOf(error: ErrorObject): string {
    const params = error.params as Record<string, unknown>;
    const field = params["missingProperty"] ?? params["additionalProperty"] ?? params["unevaluatedProperty"];
    return typeof field === "string" ? `${error.instancePath}/${field.replaceAll("~", "~0").replaceAll("/", "~1")}` : error.instancePath;
}
