# Tailwind CSS v3 to v4 Migration Guide

This guide documents the process for upgrading VibeTunnel from Tailwind CSS v3 to v4.

## Current Status

VibeTunnel currently uses Tailwind CSS v3.4.17 (see `web/package.json:152`).

## Prerequisites

- **Node.js 20 or higher** - The upgrade tool requires Node.js 20+
- **Clean git branch** - Always run the migration in a new branch
- **All changes committed** - Ensure your working directory is clean

## Automated Migration

Tailwind provides an automated upgrade tool that handles most of the migration:

```bash
cd web
npx @tailwindcss/upgrade@next
```

### What the Tool Does

The upgrade tool automatically:
- Updates dependencies to v4
- Migrates `tailwind.config.js` to CSS format
- Updates template files for breaking changes
- Converts deprecated utilities to modern alternatives
- Updates import statements

### Important Notes

- The tool only works on v3 projects. If you've partially upgraded, it will refuse to run
- To re-run after a partial upgrade, first reinstall v3: `npm install tailwindcss@3`
- Run in a new git branch to easily review changes
- Expect to spend 2-4 hours on migration for a medium project

## Major Changes in v4

### 1. CSS Import Syntax

**Before (v3):**
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

**After (v4):**
```css
@import "tailwindcss";
```

### 2. Configuration Changes

- `tailwind.config.js` is no longer needed
- Configuration moves to CSS using `@theme` and `@plugin` directives
- Zero-config by default - just import and start using

### 3. Plugin Installation

**Before (v3):**
```js
// tailwind.config.js
module.exports = {
  plugins: [
    require('@tailwindcss/typography'),
    require('@tailwindcss/forms'),
  ]
}
```

**After (v4):**
```css
@import "tailwindcss";
@plugin "@tailwindcss/typography";
@plugin "@tailwindcss/forms";
```

### 4. Dark Mode Configuration

**Default:** Uses `prefers-color-scheme` media query

**For class-based dark mode:**
```css
@import "tailwindcss";
@custom-variant dark (&:where(.dark, .dark *));
```

### 5. PostCSS Changes

The PostCSS plugin moved to a separate package:
```bash
npm install @tailwindcss/postcss
```

Update your PostCSS config to use the new package.

## Breaking Changes

### Removed Utilities

Deprecated v3 utilities have been removed. The upgrade tool handles replacements automatically.

### CSS Variable Syntax

**Before (v3):**
```html
<div class="bg-[--my-color]">
```

**After (v4):**
```html
<div class="bg-(--my-color)">
```

### Container Queries

Container queries are now built-in. Remove `@tailwindcss/container-queries` plugin.

### Renamed Scales

Default shadow, radius, and blur scales renamed for consistency. The upgrade tool handles this.

## Limitations

### SCSS/Sass Files

- The upgrade tool doesn't support `.scss` or `.less` files
- v4 isn't compatible with Sass/SCSS syntax
- Consider migrating to plain CSS (v4 supports native CSS nesting)

### Complex Configurations

Some complex configurations may need manual migration:
- Custom plugins with complex logic
- Advanced theme extensions
- Non-standard build setups

## Migration Checklist

1. **Preparation**
   ```bash
   # Ensure Node.js 20+
   node --version
   
   # Create new branch
   git checkout -b upgrade-tailwind-v4
   
   # Ensure clean working directory
   git status
   ```

2. **Run Migration**
   ```bash
   cd web
   npx @tailwindcss/upgrade@next
   ```

3. **Review Changes**
   - Check git diff carefully
   - Look for any migration warnings
   - Review updated import statements

4. **Test Thoroughly**
   ```bash
   # Start development server
   pnpm run dev
   
   # Run quality checks
   pnpm run check
   ```

5. **Manual Fixes**
   - Address any remaining warnings
   - Update custom plugins if needed
   - Fix any styling issues

6. **Verify Production Build**
   ```bash
   pnpm run build
   ```

## Performance Benefits

v4 brings significant performance improvements:
- **5x faster** full builds
- **100x faster** incremental builds (measured in microseconds)
- Smaller CSS output
- Better tree-shaking

## Alternative Tools

**TWShift** - AI-powered migration tool for complex configurations:
- Better handling of complex themes
- Keyframes and animations support
- Advanced plugin migration
- Available at: https://twshift.com/

## Rollback Plan

If issues arise:
1. Keep the migration branch separate until fully tested
2. Can always revert to v3 by switching branches
3. v3.4 will continue to receive security updates

## Resources

- [Official Upgrade Guide](https://tailwindcss.com/docs/upgrade-guide)
- [Tailwind CSS v4 Announcement](https://tailwindcss.com/blog/tailwindcss-v4)
- [Migration Discussions](https://github.com/tailwindlabs/tailwindcss/discussions)

## Browser Support

v4 requires:
- Safari 16.4+
- Chrome 111+
- Firefox 128+

If you need older browser support, stay on v3.4.