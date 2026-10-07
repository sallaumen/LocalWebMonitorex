import {webkit} from "playwright";

const [url, output] = process.argv.slice(2);
let browser;

try {
  browser = await webkit.launch({headless: true, timeout: 5000});
  const context = await browser.newContext({
    viewport: {width: 1280, height: 720},
    deviceScaleFactor: 1,
    ignoreHTTPSErrors: true,
    reducedMotion: "reduce",
  });
  await context.route("**/*", route => {
    const target = new URL(route.request().url());
    const local = ["localhost", "127.0.0.1", "[::1]"].includes(target.hostname);
    const web = ["http:", "https:"].includes(target.protocol);
    return local && web ? route.continue() : route.abort();
  });
  const page = await context.newPage();
  await page.goto(url, {waitUntil: "domcontentloaded", timeout: 4000});
  await page.waitForTimeout(500);
  await page.screenshot({path: output, timeout: 4000, animations: "disabled"});
  await context.close();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (browser) await browser.close();
}
