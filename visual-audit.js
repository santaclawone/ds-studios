const puppeteer = require('puppeteer');

const url = process.argv[2];
if (!url) { console.error('Usage: node visual-audit.js <url>'); process.exit(1); }

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36');

  try {
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    await new Promise(r => setTimeout(r, 2000));

    const results = await page.evaluate(() => {
      const issues = [];
      const pos = [];
      const styles = getComputedStyle(document.body);

      // 1. Typography check
      const fontFamily = styles.fontFamily;
      const fontSize = styles.fontSize;
      if (fontFamily.includes('Times') || fontFamily.includes('serif') && !fontFamily.includes('sans')) {
        issues.push({ type: 'design', label: 'Uses serif font for body text', severity: 'medium', detail: `Body font: ${fontFamily}. Serif fonts are harder to read on screens and look dated.`, check: 'Look at the text on the page. Does it use clean sans-serif fonts or old-style serif?', siteHint: 'Modern sites use sans-serif fonts (Arial, Helvetica, system-ui) for body text.' });
      } else {
        pos.push('Clean sans-serif body font');
      }

      // 2. Check if page looks modern (uses CSS grid, flexbox, custom properties, etc.)
      const hasCSSGrid = document.querySelector('[style*="display: grid"], [style*="display:grid"]') !== null ||
                         [...document.querySelectorAll('*')].some(el => getComputedStyle(el).display === 'grid');
      const hasFlexbox = [...document.querySelectorAll('*')].some(el => getComputedStyle(el).display === 'flex' || getComputedStyle(el).display === 'inline-flex');
      const hasCustomProps = document.querySelector('[style*="var(--"]') !== null || document.querySelector('style')?.innerHTML?.includes('--');

      if (!hasCSSGrid && !hasFlexbox) {
        issues.push({ type: 'design', label: 'Outdated layout method (no Flexbox/Grid)', severity: 'medium', detail: 'The page uses float/tables for layout instead of modern CSS Flexbox or Grid.', check: 'Resize the browser window. Does content stack or overlap? If it doesn\'t adapt well, layout is outdated.', siteHint: 'Flexbox and CSS Grid are standard. Their absence suggests the site hasn\'t been updated in 5+ years.' });
      } else {
        pos.push('Uses modern CSS layout (Flexbox/Grid)');
      }

      // 3. Color palette analysis — collect all used colors
      const colorSet = new Set();
      const els = document.querySelectorAll('*');
      els.forEach(el => {
        try {
          const cs = getComputedStyle(el);
          ['color', 'backgroundColor', 'borderColor'].forEach(prop => {
            const val = cs[prop];
            if (val && val !== 'transparent' && val !== 'rgba(0, 0, 0, 0)' && val !== 'initial' && !val.startsWith('var(')) {
              colorSet.add(val);
            }
          });
        } catch(e) {}
      });

      const colors = [...colorSet].slice(0, 30);
      const uniqueColors = colors.filter(c => !c.includes('255, 255, 255') && !c.includes('0, 0, 0'));
      if (uniqueColors.length <= 2) {
        issues.push({ type: 'design', label: 'Very limited color palette', severity: 'low', detail: `Only ${uniqueColors.length} distinct colors used on the page. Limited palette can look monotonous.`, check: 'Look at the site. Does everything look the same shade? Could use a secondary accent color.', siteHint: '2-4 complementary colors create visual hierarchy and make sites feel designed.' });
      }

      // 4. Check for images
      const images = document.querySelectorAll('img');
      const imgCount = images.length;
      const brokenImgs = [...images].filter(i => !i.complete || i.naturalWidth === 0 || i.naturalHeight === 0).length;
      const lazyImgs = [...images].filter(i => i.loading === 'lazy').length;
      const hasPlaceholder = [...images].some(i => i.naturalWidth < 50 && i.naturalHeight < 50);

      if (imgCount === 0) {
        issues.push({ type: 'design', label: 'No images on the page', severity: 'high', detail: 'Pages without images feel empty and unprofessional.', check: 'Scroll the page. Is there any photography, illustration, or icon?', siteHint: 'Even simple icons improve visual appeal and user engagement.' });
      }
      if (brokenImgs > 0) {
        issues.push({ type: 'design', label: `${brokenImgs} broken image(s)`, severity: 'medium', detail: 'Images that fail to load show blank boxes or broken icons.', check: 'Scroll through the page. Do you see any broken image icons?', siteHint: 'Broken images look unprofessional. Each one should load properly.' });
      }
      if (hasPlaceholder) {
        issues.push({ type: 'design', label: 'Placeholder/low-quality images detected', severity: 'low', detail: 'Some images appear to be placeholders (very small dimensions).', check: 'Do any images look like grey boxes or low-res blurs where real images should be?', siteHint: 'Replace placeholder images with actual photography or graphics.' });
      }

      // 5. Check for responsive design via viewport
      const viewportMeta = document.querySelector('meta[name="viewport"]');
      if (!viewportMeta) {
        issues.push({ type: 'design', label: 'No viewport meta tag (not mobile responsive)', severity: 'critical', detail: 'The page lacks a viewport meta tag and will not scale properly on mobile devices.', check: 'Open the site on a phone. Does text overflow? Do you need to zoom?', siteHint: 'Over 60% of traffic is mobile. Without responsive design, you lose visitors.' });
      } else {
        const vpContent = viewportMeta.getAttribute('content') || '';
        if (vpContent.includes('user-scalable=no')) {
          issues.push({ type: 'design', label: 'User zoom disabled', severity: 'medium', detail: 'The viewport tag has user-scalable=no, preventing visitors from zooming.', check: 'On a phone, try pinch-to-zoom. If it doesn\'t work, user-scalable is disabled.', siteHint: 'Preventing zoom makes the site inaccessible for users with visual impairments.' });
        }
        pos.push('Viewport meta tag present (mobile-friendly setup)');
      }

      // 6. Check for corner radius / rounded design (modern design signal)
      const hasRounded = [...els].some(el => {
        const r = getComputedStyle(el).borderRadius;
        return r && r !== '0px' && r !== '0';
      });
      if (hasRounded) pos.push('Uses modern rounded corners / cards');

      // 7. Check for shadows/depth
      const hasShadows = [...els].some(el => {
        const b = getComputedStyle(el).boxShadow;
        return b && b !== 'none';
      });
      if (hasShadows) pos.push('Uses shadows for visual depth');

      // 8. Favicon check
      const favicon = document.querySelector('link[rel*="icon"]');
      if (!favicon) {
        issues.push({ type: 'design', label: 'No favicon', severity: 'low', detail: 'Browser tabs show a blank icon instead of your brand.', check: 'Look at the browser tab. Is there a small icon next to the page title?', siteHint: 'A favicon reinforces brand identity and makes tabs recognizable.' });
      }

      // 9. Loading experience
      const hasLoadingSpinner = document.body.innerHTML.includes('spinner') || document.body.innerHTML.includes('loading');
      const hasSkeleton = document.body.innerHTML.includes('skeleton') || document.body.innerHTML.includes('placeholder');

      // 10. Check for overly large hero sections
      const firstSection = document.querySelector('section, header, div:first-of-type');
      if (firstSection) {
        const sectionStyle = getComputedStyle(firstSection);
        if (sectionStyle.minHeight === '100vh' || sectionStyle.height === '100vh') {
          pos.push('Full-screen hero section (modern layout pattern)');
        }
      }

      return { issues, positives: pos, colors, imgCount };
    });

    // Output as JSON for the PowerShell script to consume
    console.log(JSON.stringify(results));

  } catch (err) {
    console.error(JSON.stringify({ error: err.message }));
    process.exit(1);
  } finally {
    await browser.close();
  }
})();
