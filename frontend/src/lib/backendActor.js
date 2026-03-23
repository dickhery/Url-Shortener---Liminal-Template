import { Actor, HttpAgent } from '@dfinity/agent';
import { canisterId } from './canisters.js';
import { getIdentity } from './auth.js';

const isLocalHost = (hostname) =>
  hostname === 'localhost' || hostname === '127.0.0.1' || hostname.endsWith('.localhost');

const getHost = () => {
  if (typeof window === 'undefined') {
    return 'http://127.0.0.1:4943';
  }

  const { protocol, hostname, port } = window.location;
  if (isLocalHost(hostname)) {
    return `http://127.0.0.1:${port || '4943'}`;
  }

  return `${protocol}//${hostname}`;
};

const idlFactory = ({ IDL }) => {
  const CreateRequest = IDL.Record({
    originalUrl: IDL.Text,
    customSlug: IDL.Opt(IDL.Text),
    purchasedClicks: IDL.Nat
  });
  const UrlMetadata = IDL.Record({
    title: IDL.Opt(IDL.Text),
    description: IDL.Opt(IDL.Text),
    imageUrl: IDL.Opt(IDL.Text),
    canonicalUrl: IDL.Opt(IDL.Text),
    siteName: IDL.Opt(IDL.Text),
  });
  const UrlAllowanceView = IDL.Record({
    totalPurchasedClicks: IDL.Nat,
    remainingClicks: IDL.Nat,
    isActive: IDL.Bool,
  });
  const UrlView = IDL.Record({
    id: IDL.Nat,
    originalUrl: IDL.Text,
    shortCode: IDL.Text,
    clicks: IDL.Nat,
    createdAt: IDL.Int,
    metadata: IDL.Opt(UrlMetadata),
    allowance: UrlAllowanceView,
  });
  const WalletInfo = IDL.Record({
    canisterPrincipal: IDL.Principal,
    depositAccountId: IDL.Text,
    subaccountHex: IDL.Text,
    balanceE8s: IDL.Nat,
    transferFeeE8s: IDL.Nat,
    clickBundleSize: IDL.Nat,
    clickBundlePriceE8s: IDL.Nat,
    minimumPurchaseClicks: IDL.Nat,
    minimumPurchaseCostE8s: IDL.Nat,
    paymentTargetAccountId: IDL.Text
  });
  const ResultUrl = IDL.Variant({ ok: UrlView, err: IDL.Text });
  const ResultUnit = IDL.Variant({ ok: IDL.Null, err: IDL.Text });
  const ResultNat = IDL.Variant({ ok: IDL.Nat, err: IDL.Text });
  const ResultBool = IDL.Variant({ ok: IDL.Bool, err: IDL.Text });
  const ResultText = IDL.Variant({ ok: IDL.Text, err: IDL.Text });

  return IDL.Service({
    check_short_code_availability: IDL.Func([IDL.Text], [ResultBool], ['query']),
    create_my_url: IDL.Func([CreateRequest], [ResultUrl], []),
    delete_my_url: IDL.Func([IDL.Nat], [ResultUnit], []),
    get_public_url: IDL.Func([IDL.Text], [IDL.Opt(UrlView)], ['query']),
    get_wallet_info: IDL.Func([], [WalletInfo], []),
    list_my_urls: IDL.Func([], [IDL.Vec(UrlView)], ['query']),
    record_short_link_visit: IDL.Func([IDL.Text], [ResultUrl], []),
    refresh_all_missing_metadata: IDL.Func([], [ResultNat], []),
    refresh_my_url_metadata: IDL.Func([IDL.Nat], [ResultUrl], []),
    reserve_short_code_preview: IDL.Func([IDL.Opt(IDL.Text)], [ResultText], []),
    reserve_auto_short_code_preview: IDL.Func([], [ResultText], []),
    save_my_url_metadata: IDL.Func([IDL.Nat, UrlMetadata], [ResultUrl], []),
    top_up_my_url: IDL.Func([IDL.Nat, IDL.Nat], [ResultUrl], []),
    withdraw_from_wallet: IDL.Func([IDL.Text, IDL.Nat], [ResultUnit], []),
    whoami: IDL.Func([], [IDL.Principal], ['query'])
  });
};

let actorPromise;

export const getBackendActor = async () => {
  if (!actorPromise) {
    actorPromise = (async () => {
      const identity = await getIdentity();
      const agent = new HttpAgent({ host: getHost(), identity });

      if (typeof window !== 'undefined' && isLocalHost(window.location.hostname)) {
        await agent.fetchRootKey();
      }

      return Actor.createActor(idlFactory, { agent, canisterId });
    })();
  }

  return actorPromise;
};

export const resetBackendActor = () => {
  actorPromise = undefined;
};
