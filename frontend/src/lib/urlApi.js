import { getBackendActor } from "./backendActor.js";
import {
  buildShortLink,
  buildShortLinkPrefix,
  getBackendOrigin,
  getPublicShortLinkOrigin,
} from "./urlConfig.js";

const unwrapResult = (result, action) => {
  if ("ok" in result) {
    return result.ok;
  }

  throw new Error(result.err || `Failed to ${action}`);
};

const unwrapOptional = (value) => {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }

  return value ?? null;
};

const hasText = (value) => typeof value === "string" && value.trim().length > 0;

const normalizeMetadata = (metadata) => {
  const raw = unwrapOptional(metadata);
  if (!raw) {
    return null;
  }

  return {
    title: unwrapOptional(raw.title),
    description: unwrapOptional(raw.description),
    imageUrl: unwrapOptional(raw.imageUrl),
    canonicalUrl: unwrapOptional(raw.canonicalUrl),
    siteName: unwrapOptional(raw.siteName),
  };
};

const normalizeAllowance = (allowance) => ({
  totalPurchasedClicks: Number(allowance.totalPurchasedClicks),
  remainingClicks: Number(allowance.remainingClicks),
  isActive: Boolean(allowance.isActive),
});

const normalizeUrl = (url) => ({
  ...url,
  id: Number(url.id),
  clicks: Number(url.clicks),
  createdAt: Number(url.createdAt),
  metadata: normalizeMetadata(url.metadata),
  allowance: normalizeAllowance(url.allowance),
});

const toOptional = (value) => (hasText(value) ? [value.trim()] : []);

const toActorMetadata = (metadata) => ({
  title: toOptional(metadata?.title),
  description: toOptional(metadata?.description),
  imageUrl: toOptional(metadata?.imageUrl),
  canonicalUrl: toOptional(metadata?.canonicalUrl),
  siteName: toOptional(metadata?.siteName),
});

const resolveMetadataUrl = (value, baseUrl) => {
  if (!hasText(value)) {
    return null;
  }

  try {
    return new URL(value.trim(), baseUrl).href;
  } catch {
    return null;
  }
};

const getMetaContent = (doc, selectors) => {
  for (const selector of selectors) {
    const element = doc.querySelector(selector);
    const content = element?.getAttribute("content")?.trim();
    if (content) {
      return content;
    }
  }

  return null;
};

const getLinkHref = (doc, rel) => {
  const href = doc
    .querySelector(`link[rel="${rel}"]`)
    ?.getAttribute("href")
    ?.trim();
  return href || null;
};

const normalizeHarvestedMetadata = (metadata) => {
  if (!metadata) {
    return null;
  }

  const normalized = {
    title: hasText(metadata.title) ? metadata.title.trim() : null,
    description: hasText(metadata.description) ? metadata.description.trim() : null,
    imageUrl: hasText(metadata.imageUrl) ? metadata.imageUrl.trim() : null,
    canonicalUrl: hasText(metadata.canonicalUrl) ? metadata.canonicalUrl.trim() : null,
    siteName: hasText(metadata.siteName) ? metadata.siteName.trim() : null,
  };

  return Object.values(normalized).some(hasText) ? normalized : null;
};

const extractMetadataFromHtml = (html, originalUrl) => {
  if (typeof DOMParser === "undefined") {
    throw new Error("Browser metadata extraction is not available in this environment");
  }

  const doc = new DOMParser().parseFromString(html, "text/html");
  const title =
    getMetaContent(doc, [
      'meta[property="og:title"]',
      'meta[name="twitter:title"]',
    ]) ||
    doc.querySelector("title")?.textContent?.trim() ||
    null;
  const description =
    getMetaContent(doc, [
      'meta[property="og:description"]',
      'meta[name="twitter:description"]',
      'meta[name="description"]',
    ]) || null;
  const imageUrl = resolveMetadataUrl(
    getMetaContent(doc, [
      'meta[property="og:image"]',
      'meta[property="og:image:url"]',
      'meta[name="twitter:image"]',
      'meta[name="twitter:image:src"]',
    ]) || getLinkHref(doc, "image_src"),
    originalUrl,
  );
  const canonicalUrl = resolveMetadataUrl(
    getMetaContent(doc, ['meta[property="og:url"]']) || getLinkHref(doc, "canonical"),
    originalUrl,
  );
  const siteName =
    getMetaContent(doc, ['meta[property="og:site_name"]']) || null;

  return normalizeHarvestedMetadata({
    title,
    description,
    imageUrl,
    canonicalUrl,
    siteName,
  });
};

const normalizeWallet = (wallet) => ({
  ...wallet,
  canisterPrincipal: wallet.canisterPrincipal.toText(),
  balanceE8s: Number(wallet.balanceE8s),
  transferFeeE8s: Number(wallet.transferFeeE8s),
  clickBundleSize: Number(wallet.clickBundleSize),
  clickBundlePriceE8s: Number(wallet.clickBundlePriceE8s),
  minimumPurchaseClicks: Number(wallet.minimumPurchaseClicks),
  minimumPurchaseCostE8s: Number(wallet.minimumPurchaseCostE8s),
  paymentTargetAccountId: wallet.paymentTargetAccountId,
});

export const formatIcp = (e8s) => {
  const value = Number(e8s) / 100_000_000;

  if (value === 0) {
    return '0.0000';
  }

  return value
    .toFixed(4)
    .replace(/(\.\d*?[1-9])0+$/, '$1')
    .replace(/\.0+$/, '');
};

export class UrlApi {
  static async getAllUrls() {
    const actor = await getBackendActor();
    const urls = await actor.list_my_urls();
    return urls.map(normalizeUrl);
  }

  static async getPublicUrl(shortCode) {
    if (!hasText(shortCode)) {
      throw new Error("Short code is required");
    }

    const actor = await getBackendActor();
    const url = unwrapOptional(await actor.get_public_url(shortCode.trim()));
    return url ? normalizeUrl(url) : null;
  }

  static async getWalletInfo() {
    const actor = await getBackendActor();
    return normalizeWallet(await actor.get_wallet_info());
  }

  static async recordShortLinkVisit(shortCode) {
    if (!hasText(shortCode)) {
      throw new Error("Short code is required");
    }

    const actor = await getBackendActor();
    const result = await actor.record_short_link_visit(shortCode.trim());
    return normalizeUrl(unwrapResult(result, "record short URL visit"));
  }

  static async createShortUrl(originalUrl, customSlug = null, purchasedClicks) {
    if (!originalUrl || !originalUrl.trim()) {
      throw new Error("Original URL is required");
    }

    if (!Number.isFinite(purchasedClicks) || purchasedClicks <= 0) {
      throw new Error("A prepaid click amount is required");
    }

    try {
      new URL(originalUrl);
    } catch {
      throw new Error("Invalid URL format");
    }

    const actor = await getBackendActor();
    const result = await actor.create_my_url({
      originalUrl,
      purchasedClicks: BigInt(purchasedClicks),
      customSlug: customSlug ? [customSlug] : [],
    });

    return normalizeUrl(unwrapResult(result, "create short URL"));
  }

  static async topUpUrl(id, purchasedClicks) {
    if (!Number.isFinite(purchasedClicks) || purchasedClicks <= 0) {
      throw new Error("A prepaid click amount is required");
    }

    const actor = await getBackendActor();
    const result = await actor.top_up_my_url(BigInt(id), BigInt(purchasedClicks));
    return normalizeUrl(unwrapResult(result, "top up URL clicks"));
  }

  static async deleteUrl(id) {
    const actor = await getBackendActor();
    const result = await actor.delete_my_url(BigInt(id));
    unwrapResult(result, "delete URL");
  }

  static async refreshUrlMetadata(id) {
    const actor = await getBackendActor();
    const result = await actor.refresh_my_url_metadata(BigInt(id));
    return normalizeUrl(unwrapResult(result, "refresh preview metadata"));
  }

  static async checkShortCodeAvailability(shortCode) {
    if (!hasText(shortCode)) {
      throw new Error("Short code is required");
    }

    const actor = await getBackendActor();
    return unwrapResult(
      await actor.check_short_code_availability(shortCode.trim()),
      "check short code availability",
    );
  }

  static async reserveAutoShortCodePreview() {
    return this.reserveShortCodePreview(null);
  }

  static async reserveShortCodePreview(shortCode = null) {
    const actor = await getBackendActor();
    return unwrapResult(
      await actor.reserve_short_code_preview(shortCode ? [shortCode.trim()] : []),
      "reserve short code preview",
    );
  }

  static async saveUrlMetadata(id, metadata) {
    const actor = await getBackendActor();
    const result = await actor.save_my_url_metadata(
      BigInt(id),
      toActorMetadata(metadata),
    );
    return normalizeUrl(unwrapResult(result, "save preview metadata"));
  }

  static async refreshAllMissingMetadata() {
    const actor = await getBackendActor();
    const result = await actor.refresh_all_missing_metadata();
    return Number(unwrapResult(result, "refresh missing preview metadata"));
  }

  static async harvestMetadataInBrowser(originalUrl) {
    if (!hasText(originalUrl)) {
      throw new Error("Original URL is required");
    }

    const response = await fetch(originalUrl, {
      method: "GET",
      headers: {
        Accept: "text/html,application/xhtml+xml",
      },
    });

    if (!response.ok) {
      throw new Error(
        `Browser fetch failed with ${response.status} ${response.statusText}`,
      );
    }

    const html = await response.text();
    const metadata = extractMetadataFromHtml(html, originalUrl);

    if (!metadata) {
      throw new Error("The destination page did not expose usable preview metadata");
    }

    return metadata;
  }

  static async withdrawFromWallet(destinationAccountId, amountE8s) {
    if (!destinationAccountId || !destinationAccountId.trim()) {
      throw new Error("Destination account ID is required");
    }

    if (!Number.isFinite(amountE8s) || amountE8s <= 0) {
      throw new Error("Withdrawal amount must be greater than zero");
    }

    const actor = await getBackendActor();
    const result = await actor.withdraw_from_wallet(
      destinationAccountId.trim(),
      BigInt(Math.round(amountE8s)),
    );
    unwrapResult(result, "withdraw ICP from wallet");
  }

  static getPublicShortUrl(shortCode) {
    return buildShortLink(getPublicShortLinkOrigin(), shortCode);
  }

  static getPublicShortUrlPrefix() {
    return buildShortLinkPrefix(getPublicShortLinkOrigin());
  }

  static getShortUrl(shortCode) {
    return this.getPublicShortUrl(shortCode);
  }

  static getBackendShortUrl(shortCode, raw = false) {
    return buildShortLink(getBackendOrigin(raw), shortCode);
  }

  static async getUrlStats(shortCode) {
    const response = await fetch(`${this.getBackendShortUrl(shortCode, true)}/stats`, {
      method: "GET",
      headers: {
        Accept: "application/json",
      },
    });

    if (!response.ok) {
      if (response.status === 404) {
        throw new Error(`Short URL ${shortCode} not found`);
      }
      throw new Error(
        `Failed to fetch URL stats: ${response.status} ${response.statusText}`,
      );
    }

    return await response.json();
  }
}

export default UrlApi;
