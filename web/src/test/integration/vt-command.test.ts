import { execSync, spawn } from 'child_process';
import { existsSync } from 'fs';
import { join } from 'path';
import { beforeAll, describe, expect, it } from 'vitest';

describe('vt command', () => {
  const projectRoot = join(__dirname, '../../..');
  const vtScriptPath = join(projectRoot, 'bin/vt');
  const packageJsonPath = join(projectRoot, 'package.json');

  beforeAll(() => {
    // Ensure the vt script exists
    expect(existsSync(vtScriptPath)).toBe(true);
    expect(existsSync(packageJsonPath)).toBe(true);
  });

  it('should have valid bash syntax', () => {
    // Test bash syntax using bash -n (no-exec mode)
    expect(() => {
      execSync(`bash -n "${vtScriptPath}"`, {
        stdio: 'pipe',
        cwd: projectRoot,
      });
    }).not.toThrow();
  });

  it('should be executable', () => {
    const stats = require('fs').statSync(vtScriptPath);
    expect(stats.mode & 0o111).toBeTruthy(); // Check execute permissions
  });

  it('should NOT be included in package.json bin section', () => {
    const packageJson = JSON.parse(require('fs').readFileSync(packageJsonPath, 'utf8'));
    expect(packageJson.bin).toBeDefined();
    // vt should NOT be in bin section to avoid conflicts with other tools
    expect(packageJson.bin.vt).toBeUndefined();
    expect(packageJson.bin.vibetunnel).toBe('./bin/vibetunnel');
  });

  it('should show help when called with --help', (done) => {
    const child = spawn('bash', [vtScriptPath, '--help'], {
      cwd: projectRoot,
      stdio: 'pipe',
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    child.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    child.on('close', (code) => {
      try {
        // Should exit with code 0 for help
        expect(code).toBe(0);

        // Should contain help content
        expect(stdout).toContain('vt - VibeTunnel TTY Forward Wrapper');
        expect(stdout).toContain('USAGE:');
        expect(stdout).toContain('EXAMPLES:');
        expect(stdout).toContain('OPTIONS:');

        // Should show binary path information
        expect(stdout).toContain('VIBETUNNEL BINARY:');
        expect(stdout).toContain('Path:');

        // Should not have errors
        expect(stderr).toBe('');

        done();
      } catch (error) {
        done(error);
      }
    });

    child.on('error', (error) => {
      done(error);
    });
  }, 10000); // 10 second timeout

  it('should show help when called with no arguments', (done) => {
    const child = spawn('bash', [vtScriptPath], {
      cwd: projectRoot,
      stdio: 'pipe',
    });

    let stdout = '';
    let _stderr = '';

    child.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    child.stderr.on('data', (data) => {
      _stderr += data.toString();
    });

    child.on('close', (code) => {
      try {
        // Should exit with code 0 for help
        expect(code).toBe(0);

        // Should contain help content
        expect(stdout).toContain('vt - VibeTunnel TTY Forward Wrapper');
        expect(stdout).toContain('USAGE:');

        done();
      } catch (error) {
        done(error);
      }
    });

    child.on('error', (error) => {
      done(error);
    });
  }, 10000);

  it('should handle title command outside session correctly', (done) => {
    const child = spawn('bash', [vtScriptPath, 'title', 'test'], {
      cwd: projectRoot,
      stdio: 'pipe',
      env: { ...process.env, VIBETUNNEL_SESSION_ID: '' }, // Ensure no session ID
    });

    let _stdout = '';
    let stderr = '';

    child.stdout.on('data', (data) => {
      _stdout += data.toString();
    });

    child.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    child.on('close', (code) => {
      try {
        // Should exit with code 1 for error
        expect(code).toBe(1);

        // Should show error message
        expect(stderr).toContain("vt title' can only be used inside a VibeTunnel session");

        done();
      } catch (error) {
        done(error);
      }
    });

    child.on('error', (error) => {
      done(error);
    });
  }, 10000);

  it('should detect if script contains required functions', () => {
    const scriptContent = require('fs').readFileSync(vtScriptPath, 'utf8');

    // Check for essential functions and structures
    expect(scriptContent).toContain('show_help()');
    expect(scriptContent).toContain('resolve_command()');
    expect(scriptContent).toContain('VIBETUNNEL_BIN');
    expect(scriptContent).toContain('exec "$VIBETUNNEL_BIN"');

    // Check for critical conditionals
    expect(scriptContent).toContain('if [ -z "$VIBETUNNEL_BIN" ]');
    expect(scriptContent).toContain('if [ -n "$VIBETUNNEL_SESSION_ID" ]');

    // Check that follow command handling exists
    expect(scriptContent).toContain('if [[ "$1" == "follow" ]]');
    expect(scriptContent).toContain('if [[ "$1" == "unfollow" ]]');
  });

  it('should be included in npm package files', () => {
    const packageJson = JSON.parse(require('fs').readFileSync(packageJsonPath, 'utf8'));
    expect(packageJson.files).toContain('bin/');
  });
});
