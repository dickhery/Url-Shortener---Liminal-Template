import { spawnSync } from 'node:child_process';

const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, {
    stdio: 'inherit',
    shell: process.platform === 'win32',
    ...options,
  });

  if (result.error) {
    if (result.error.code === 'ENOENT') {
      return { skipped: true };
    }
    throw result.error;
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }

  return { skipped: false };
};

const dfxCheck = spawnSync('dfx', ['--version'], {
  stdio: 'ignore',
  shell: process.platform === 'win32',
});

if (dfxCheck.error?.code === 'ENOENT') {
  console.warn('[prepare-frontend] Skipping `dfx generate backend` because `dfx` is not installed in PATH.');
  process.exit(0);
}

if (dfxCheck.status !== 0) {
  process.exit(dfxCheck.status ?? 1);
}

run('dfx', ['generate', 'backend']);
