import { AuthClient } from '@dfinity/auth-client';
import { building } from '$app/environment';

const MAINNET_II_URL = 'https://identity.ic0.app';

let authClientPromise;


export const getIdentityProvider = () => {
  if (building || typeof window === 'undefined') {
    return MAINNET_II_URL;
  }

  const configured = import.meta.env.VITE_INTERNET_IDENTITY_URL;
  if (configured) {
    return configured;
  }

  return MAINNET_II_URL;
};

export const getAuthClient = async () => {
  if (!authClientPromise) {
    authClientPromise = AuthClient.create();
  }

  return authClientPromise;
};

export const isAuthenticated = async () => {
  const client = await getAuthClient();
  return client.isAuthenticated();
};

export const getIdentity = async () => {
  const client = await getAuthClient();
  return client.getIdentity();
};

export const login = async () => {
  const client = await getAuthClient();

  return new Promise((resolve, reject) => {
    client.login({
      identityProvider: getIdentityProvider(),
      onSuccess: resolve,
      onError: reject,
      windowOpenerFeatures: 'toolbar=0,location=0,menubar=0,width=520,height=705,left=100,top=100'
    });
  });
};

export const logout = async () => {
  const client = await getAuthClient();
  await client.logout();
};

export const getPrincipalText = async () => {
  const identity = await getIdentity();
  return identity.getPrincipal().toText();
};
