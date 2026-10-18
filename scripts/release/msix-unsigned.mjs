// Pack the staged SliceApp payload into an UNSIGNED MSIX with the same inputs right-release would use
// (examples/SliceApp/right-release.config.mjs targets.win.msix: identity, virtualization, assets, runtime inventory,
// App Installer). right-release `build` refuses unsigned targets, so this calls the packer it ships (msix-target.mjs,
// msix-build.mjs) with sign:false. The package is not installable until the windows-sign job signs it.
import { pathToFileURL } from "node:url";
import path from "node:path";

const root = path.resolve("examples/SliceApp");
const release = path.resolve("node_modules/@rightkit/release");
const config = (await import(pathToFileURL(path.join(root, "right-release.config.mjs")).href)).default;
const { msixBuildOptions } = await import(pathToFileURL(path.join(release, "msix-target.mjs")).href);
const { buildMsix } = await import(pathToFileURL(path.join(release, "msix-build.mjs")).href);

const options = msixBuildOptions({ root, target: config.targets.win, app: config.app, sign: false });
const built = buildMsix(options, { log: (event) => console.log(JSON.stringify(event)) });
console.log(JSON.stringify({ out: built.out, signed: built.signed, seal: built.seal, appInstaller: built.appInstaller }));
