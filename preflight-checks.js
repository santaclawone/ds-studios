/**
 * preflight-checks.js
 * Safe, reversible, local-only checks that the HTML-only audit can't do:
 *   - SSL cert validity & expiry
 *   - Security headers (HSTS, CSP, X-Frame-Options)
 *   - CMS/platform detection
 *   - Subpage discovery (common paths)
 *   - HTTP/HTTPS redirect check
 * No external APIs. No data exfiltration. All local.
 */

const https = require('https');
const http = require('http');
const urlMod = require('url');

const target = process.argv[2];
if (!target) { console.error('Usage: node preflight-checks.js <url>'); process.exit(1); }

// Normalize URL
function normalizedUrl(u) {
  if (!u.startsWith('http')) u = 'https://' + u;
  return u.replace(/\/+$/, '');
}

const mainUrl = normalizedUrl(target);
const parsed = new URL(mainUrl);
const hostname = parsed.hostname;

const results = { issues: [], positives: [] };

function addIssue(label, severity, detail, check, siteHint) {
  results.issues.push({ type: 'preflight', label, severity, detail, check, siteHint });
}
function addPos(detail) {
  // Deduplicate by detail text
  if (!results.positives.some(p => p.detail === detail)) {
    results.positives.push({ detail });
  }
}

// 1. SSL Certificate check (via HTTPS GET — no external API, just reads the TLS handshake)
async function checkSsl() {
  return new Promise((resolve) => {
    if (parsed.protocol !== 'https:') {
      addIssue('No HTTPS / SSL', 'critical', 'The site does not use HTTPS. All data is sent in plain text.', 'Check if the URL starts with https://. If it starts with http://, no encryption is used.', 'Google flags non-HTTPS sites. Visitors see "Not Secure" warnings.');
      return resolve();
    }

    const options = {
      hostname,
      port: 443,
      method: 'HEAD',
      rejectUnauthorized: false,
      agent: false,
      timeout: 10000
    };

    const req = https.request(options, (res) => {
      const cert = res.socket.getPeerCertificate();
      if (!cert || !cert.subject) {
        addIssue('SSL certificate info unavailable', 'medium', 'Could not read SSL certificate details.', 'Try visiting the site with https:// in your browser.', 'Without a valid cert, visitors get security warnings.');
        return resolve();
      }

      // Check expiry
      const validTo = new Date(cert.valid_to);
      const now = new Date();
      const daysLeft = Math.floor((validTo - now) / (1000 * 60 * 60 * 24));

      if (daysLeft < 0) {
        addIssue(`SSL certificate expired ${Math.abs(daysLeft)} days ago`, 'critical', `SSL cert expired on ${cert.valid_to}. The site may show security warnings.`, 'Click the lock icon in the address bar. Does it say "Not Secure" or "Expired"?', 'An expired SSL certificate means visitors get blocked by their browser.');
      } else if (daysLeft < 14) {
        addIssue(`SSL certificate expires in ${daysLeft} days`, 'high', `SSL cert valid until ${cert.valid_to}. Needs renewal soon.`, 'Check the lock icon in the address bar for certificate details.', 'Letting the certificate lapse will make your site inaccessible.');
      } else if (daysLeft < 60) {
        addIssue(`SSL certificate expires in ${daysLeft} days`, 'low', `SSL cert renews on ${cert.valid_to}. Mark your calendar.`, 'Check the lock icon in the address bar.', 'Just a reminder — easy to forget until it is too late.');
      } else {
        addPos(`SSL certificate valid — ${daysLeft} days remaining`);
      }

      // Check issuer
      if (cert.issuer && cert.issuer.O) {
        // Let's Encrypt is fine, but paid certs signal more established
        if (cert.issuer.O.includes('Let\'s Encrypt')) {
          // Common, no issue — often used well
        }
      }

      resolve();
    });

    req.on('error', (err) => {
      addIssue('Could not verify SSL certificate', 'medium', `SSL check failed: ${err.message}`, 'Visit the site and check the lock icon in the address bar.', 'SSL issues can prevent visitors from reaching your site.');
      resolve();
    });

    req.on('timeout', () => {
      req.destroy();
      addIssue('SSL certificate check timed out', 'low', 'Could not verify SSL certificate within 10 seconds.', 'Visit the site and check manually.', 'Slow SSL handshake can indicate server issues.');
      resolve();
    });

    req.end();
  });
}

// 2. Security headers check
async function checkSecurityHeaders() {
  return new Promise((resolve) => {
    const options = {
      hostname,
      port: parsed.protocol === 'https:' ? 443 : 80,
      path: parsed.pathname || '/',
      method: 'HEAD',
      rejectUnauthorized: false,
      timeout: 10000
    };

    const mod = parsed.protocol === 'https:' ? https : http;
    const req = mod.request(options, (res) => {
      const headers = res.headers || {};
      const hsts = headers['strict-transport-security'];
      const csp = headers['content-security-policy'];
      const xfo = headers['x-frame-options'];
      const xct = headers['x-content-type-options'];

      if (!hsts) {
        addIssue('Missing HSTS header', 'low', 'HTTP Strict Transport Security tells browsers to always use HTTPS. Without it, a downgrade attack is possible.', 'Open DevTools → Network → click the first request → look for "strict-transport-security".', 'HSTS is a simple config that hardens your site against protocol downgrade attacks.');
      } else {
        addPos('HSTS (HTTP Strict Transport Security) is set');
      }

      if (!csp) {
        addIssue('Missing Content Security Policy', 'low', 'CSP helps prevent XSS attacks by controlling which resources can load.', 'Check DevTools Console for CSP-related warnings.', 'A basic CSP blocks most common script injection attacks.');
      } else {
        addPos('Content Security Policy (CSP) is configured');
      }

      if (!xfo || (xfo !== 'DENY' && xfo !== 'SAMEORIGIN')) {
        addIssue('Missing X-Frame-Options header', 'low', 'Without this, your site could be embedded in an iframe on another site (clickjacking risk).', 'Check if the site has X-Frame-Options: DENY or SAMEORIGIN in response headers.', 'Without this, others could embed your site on malicious pages.');
      } else {
        addPos('X-Frame-Options prevents clickjacking');
      }

      if (!xct) {
        addIssue('Missing X-Content-Type-Options header', 'low', 'This prevents MIME-type sniffing attacks.', 'Check DevTools Network tab for the header.', 'Minor security hardening.');
      } else {
        addPos('X-Content-Type-Options: nosniff is set');
      }

      resolve();
    });

    req.on('error', () => resolve()); // Non-critical, don't fail
    req.on('timeout', () => { req.destroy(); resolve(); });
    req.end();
  });
}

// 3. CMS / Platform detection
function detectPlatform(html) {
  if (!html) return;

  const platforms = [];

  // WordPress
  if (/wp-content|wp-includes|wp-json|wordpress|\.org/i.test(html)) {
    platforms.push({ name: 'WordPress', severity: 'info', isDIY: false });
  }
  // Wix
  if (/wix\.com|Wix\.com|wixSite|X-UA-Compatible.*Wix/i.test(html)) {
    platforms.push({ name: 'Wix', severity: 'info', isDIY: true });
  }
  // Squarespace
  if (/squarespace|static1\.squarespace/i.test(html)) {
    platforms.push({ name: 'Squarespace', severity: 'info', isDIY: true });
  }
  // Shopify
  if (/shopify|myshopify\.com|cdn\.shopify/i.test(html)) {
    platforms.push({ name: 'Shopify', severity: 'info', isDIY: true });
  }
  // Webflow
  if (/webflow|cdn\.webflow/i.test(html)) {
    platforms.push({ name: 'Webflow', severity: 'info', isDIY: false });
  }
  // Joomla
  if (/joomla|\.joomla/i.test(html)) {
    platforms.push({ name: 'Joomla', severity: 'info', isDIY: false });
  }
  // Drupal
  if (/drupal|\.drupal/i.test(html)) {
    platforms.push({ name: 'Drupal', severity: 'info', isDIY: false });
  }
  // GoDaddy Website Builder
  if (/godaddy|GoDaddy/i.test(html)) {
    platforms.push({ name: 'GoDaddy Website Builder', severity: 'info', isDIY: true });
  }
  // Weebly
  if (/weebly\.com|\.weebly/i.test(html)) {
    platforms.push({ name: 'Weebly', severity: 'info', isDIY: true });
  }
  // Jimdo
  if (/jimdo\.com|jimdo/i.test(html)) {
    platforms.push({ name: 'Jimdo', severity: 'info', isDIY: true });
  }
  // Prestashop (ecommerce)
  if (/prestashop|\.prestashop/i.test(html)) {
    platforms.push({ name: 'PrestaShop', severity: 'info', isDIY: false });
  }

  // Detect agency/developer credits in the footer
  const agencyPatterns = [
    /designed\s+by\s+([^<.]{2,50})(?:\||\s*[-,]|\s*<|\s*\.)/i,
    /developed\s+by\s+([^<.]{2,50})(?:\||\s*[-,]|\s*<|\s*\.)/i,
    /built\s+by\s+([^<.]{2,50})(?:\||\s*[-,]|\s*<|\s*\.)/i,
    /website\s+by\s+([^<.]{2,50})(?:\||\s*[-,]|\s*<|\s*\.)/i,
    /powered\s+by\s+([^<.]{2,50})(?:\||\s*[-,]|\s*<|\s*\.)/i,
    /created\s+by\s+([^<.]{2,50})(?:\||\s*[-,]|\s*<|\s*\.)/i,
    /site\s+by\s+([^<.]{2,50})(?:\||\s*[-,]|\s*<|\s*\.)/i
  ];
  let agencyName = null;
  for (const pattern of agencyPatterns) {
    const match = html.match(pattern);
    if (match && match[1]) {
      agencyName = match[1].trim();
      break;
    }
  }
  if (platforms.length > 0) {
    // De-duplicate
    const unique = platforms.filter((p, i, arr) => arr.findIndex(x => x.name === p.name) === i);
    const isWordPress = unique.some(p => p.name === 'WordPress');

    // Flag agencies that delivered a WordPress site
    if (agencyName && isWordPress) {
      addIssue('Website credited to "' + agencyName + '" but runs on WordPress', 'low',
        'The footer credits "' + agencyName + '" as the developer, yet the underlying platform is WordPress. This suggests a pre-built theme rather than a custom build. The "developer" is essentially reselling a stock template.',
        'Scroll to the bottom of each page. Do you see "Designed by ' + agencyName + '"? They likely installed a WordPress theme.',
        'Your current "web developer" delivered a WordPress theme, not a custom site. DS Studios can build something genuinely custom.'
      );
    }

    if (unique.length === 1 && unique[0].isDIY) {
      addIssue('Using ' + unique[0].name + ' (DIY builder)', 'medium',
        'The site runs on ' + unique[0].name + ', a DIY website builder. DIY platforms limit design freedom, performance tuning, and SEO control.',
        'View page source and search for the platform name.',
        'DIY builders like ' + unique[0].name + ' are great for getting started, but as your business grows, the limitations become costly - custom features, page speed, and SEO are all capped by the platform.'
      );
    } else {
      // Multiple platforms or professional CMS
      const diyOnes = unique.filter(p => p.isDIY);
      if (diyOnes.length > 0) {
        addIssue('Using ' + diyOnes[0].name + ' (DIY builder)', 'medium',
          'The site runs on ' + diyOnes[0].name + '. This limits SEO flexibility, page speed control, and custom features.',
          'View page source and search for the platform.',
          'Businesses often outgrow ' + diyOnes[0].name + ' and need a custom site to stand out.'
        );
      }
      // Note the platform
      results.platform = unique.map(p => p.name).join(', ');
      addPos('Built with ' + unique.map(p => p.name).join(', '));
    }
  }
}

// 4. Fetch a page and check its content
function fetchPage(pageUrl) {
  return new Promise((resolve) => {
    const u = new URL(pageUrl);
    const mod = u.protocol === 'https:' ? https : http;
    const opts = {
      hostname: u.hostname,
      port: u.protocol === 'https:' ? 443 : 80,
      path: u.pathname + u.search,
      rejectUnauthorized: false,
      timeout: 10000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36'
      }
    };

    const req = mod.request(opts, (res) => {
      let data = '';
      const redirect = res.statusCode >= 300 && res.statusCode < 400 && res.headers.location;
      if (redirect) {
        // Follow one redirect
        resolve(fetchPage(new URL(redirect, pageUrl).href));
        return;
      }
      res.on('data', chunk => { data += chunk.toString('utf8'); });
      res.on('end', () => {
        resolve({ status: res.statusCode, headers: res.headers, body: data });
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
    req.end();
  });
}

// 5. Common subpages to check
const SUBPAGES = [
  '/contact', '/contact-us', '/get-in-touch', '/contactus',
  '/about', '/about-us',
  '/enquire', '/enquiries', '/book-now', '/book',
  '/services', '/our-services',
  '/reservations', '/booking'
];

async function checkSubpages(hostUrl) {
  const foundPages = [];

  for (const sp of SUBPAGES) {
    const fullUrl = hostUrl.replace(/\/+$/, '') + sp;
    const result = await fetchPage(fullUrl);
    if (result && result.status === 200 && result.body) {
      foundPages.push({
        path: sp,
        status: result.status,
        hasForm: /<form|<input[^>]+type=("|')?(text|email|tel|textarea)/i.test(result.body),
        body: result.body
      });
    }
  }

  // Check main page for forms on subpages
  const subpagesWithForms = foundPages.filter(p => p.hasForm);
  if (subpagesWithForms.length > 0) {
    addPos(`Contact form found on: ${subpagesWithForms.map(p => p.path).join(', ')}`);
    results.subpages = foundPages;
  }

  // Detect CMS from any fetched page
  for (const sp of foundPages) {
    detectPlatform(sp.body);
  }

  return foundPages;
}

// ---- MAIN EXECUTION ----
(async () => {
  // 1. SSL check
  await checkSsl();

  // 2. Security headers (on main page)
  await checkSecurityHeaders();

  // 3. Fetch main page for platform detection
  const mainPage = await fetchPage(mainUrl);
  if (mainPage && mainPage.body) {
    detectPlatform(mainPage.body);

    // Check main page for contact form (more thorough than regex)
    const hasContactForm = /<form[^>]*>.*?<(input|textarea|button)[^>]*>/is.test(mainPage.body);
    // Also check for email/mailto links
    const hasEmail = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/.test(mainPage.body);
    const hasMailto = /mailto:/i.test(mainPage.body);

    if (!hasContactForm && !hasEmail && !hasMailto) {
      // Will be checked on subpages too — add only if no form found anywhere
    }

    // HTTP → HTTPS redirect check
    if (mainPage.headers && mainPage.headers['location']) {
      addPos('HTTP to HTTPS redirect active');
    }
  }

  // 4. Check subpages
  const subpages = await checkSubpages(mainUrl);

  // If main page has no contact form, but subpage does — note that
  if (mainPage && !(/<form[^>]*>.*?(input|textarea|button)/is).test(mainPage.body)) {
    const spForm = (subpages || []).filter(p => p.hasForm);
    if (spForm.length > 0) {
      addIssue('Contact form hidden on subpage', 'medium',
        `The homepage lacks a contact form. There is one on ${spForm.map(p => p.path).join(', ')}, but visitors reaching the homepage may not find it.`,
        'Look at the top-level navigation. Is "Contact" easy to find from the homepage?',
        'A visible contact form on the main page can increase inquiries by 30-50%. Visitors should not have to hunt for it.'
      );
    }
  }

  // Strip full HTML bodies from subpages before output
  if (results.subpages) {
    results.subpages = results.subpages.map(sp => ({
      path: sp.path,
      status: sp.status,
      hasForm: sp.hasForm
    }));
  }

  // Output as JSON
  console.log(JSON.stringify(results));
})().catch(err => {
  console.log(JSON.stringify({ issues: [{ type: 'preflight', label: 'Preflight check error', severity: 'low', detail: err.message, check: '', siteHint: '' }], positives: [] }));
});
