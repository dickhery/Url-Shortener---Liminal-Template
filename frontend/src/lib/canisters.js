import { building } from '$app/environment';

const readCanisterId = () => {
  const configuredCanisterId =
    process.env.CANISTER_ID_BACKEND ??
    process.env.CANISTER_ID ??
    process.env.BACKEND_CANISTER_ID;

  if (configuredCanisterId) {
    return configuredCanisterId;
  }

  if (building || process.env.NODE_ENV === 'test') {
    return 'backend';
  }

  throw new Error(
    'Missing backend canister id. Run `dfx deploy` (or `dfx generate backend`) so DFX can populate the CANISTER_ID_BACKEND environment variable.'
  );
};

export const canisterId = readCanisterId();

export const backend = new Proxy(
  {},
  {
    get() {
      throw new Error('This app talks to the backend over HTTP. Use UrlApi instead of a generated actor.');
    },
  }
);
