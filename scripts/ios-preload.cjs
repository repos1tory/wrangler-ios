// ios-preload.cjs — make a CI Node process take the same platform branch as a
// jailbroken iOS device. Loaded with `node --require`, before the CLI entry, so
// the entry remains the main module (Wrangler only runs when it is main).
Object.defineProperty(process, "platform", { value: "ios", configurable: true });
