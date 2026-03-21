<script>
    import "../index.scss";
    import { onMount } from "svelte";
    import UrlApi, { formatIcp } from "$lib/urlApi.js";
    import { canisterId } from "$lib/canisters.js";
    import {
        getPrincipalText,
        isAuthenticated,
        login,
        logout
    } from "$lib/auth.js";
    import { resetBackendActor } from "$lib/backendActor.js";

    let urls = [];
    let wallet = null;
    let loading = false;
    let walletLoading = false;
    let walletError = "";
    let authLoading = true;
    let authenticated = false;
    let principal = "";
    let error = "";
    let successMessage = "";
    let newUrl = "";
    let customSlug = "";
    let copiedShortUrl = "";
    let copiedWalletValue = "";
    let showPurchaseModal = false;
    let pendingRequest = null;
    let withdrawalAccountId = "";
    let withdrawalAmountIcp = "";
    let refreshingPreviewIds = [];
    const customSlugPattern = /^[A-Za-z0-9_-]+$/;

    function getBackendBaseUrl(raw = true) {
        const canisterIdAndRaw = raw ? `${canisterId}.raw` : canisterId;

        if (typeof window === "undefined") {
            return `http://${canisterIdAndRaw}.localhost:4943`;
        }

        const hostname = window.location.hostname;
        const port = window.location.port || "4943";
        const isLocal =
            hostname === "localhost" ||
            hostname === "127.0.0.1" ||
            hostname.endsWith(".localhost");

        if (isLocal) {
            return `http://${canisterIdAndRaw}.localhost:${port}`;
        }

        return `https://${canisterIdAndRaw}.icp0.io`;
    }

    async function syncAuthState() {
        authLoading = true;
        error = "";

        try {
            authenticated = await isAuthenticated();
            resetBackendActor();
            principal = authenticated ? await getPrincipalText() : "";

            if (authenticated) {
                await Promise.all([loadUrls(), loadWallet()]);
            } else {
                urls = [];
                wallet = null;
            }
        } catch (err) {
            authenticated = false;
            principal = "";
            wallet = null;
            walletError = "";
            error = "Failed to initialize authentication: " + err.message;
        } finally {
            authLoading = false;
        }
    }

    async function loadUrls() {
        if (!authenticated) {
            urls = [];
            return;
        }

        loading = true;
        error = "";
        try {
            urls = await UrlApi.getAllUrls();
        } catch (err) {
            error = "Failed to load URLs: " + err.message;
            console.error("Error loading URLs:", err);
        } finally {
            loading = false;
        }
    }

    async function loadWallet() {
        if (!authenticated) {
            wallet = null;
            return;
        }

        walletLoading = true;
        walletError = "";
        try {
            wallet = await UrlApi.getWalletInfo();
        } catch (err) {
            wallet = null;
            walletError = "Failed to load wallet: " + err.message;
            console.error("Error loading wallet:", err);
        } finally {
            walletLoading = false;
        }
    }

    async function handleLogin() {
        authLoading = true;
        error = "";
        try {
            await login();
            showSuccess("Authenticated successfully. Loading your Tiny URLs...");
            await syncAuthState();
        } catch (err) {
            error = "Internet Identity sign in failed: " + err.message;
            authLoading = false;
        }
    }

    async function handleLogout() {
        authLoading = true;
        try {
            await logout();
            resetBackendActor();
            authenticated = false;
            principal = "";
            urls = [];
            wallet = null;
            walletError = "";
            showSuccess("Signed out successfully");
        } catch (err) {
            error = "Failed to sign out: " + err.message;
        } finally {
            authLoading = false;
        }
    }

    async function shortenUrl() {
        if (!newUrl.trim()) {
            error = "Please enter a URL to shorten";
            return;
        }

        try {
            new URL(newUrl);
        } catch {
            error = "Please enter a valid URL (including http:// or https://)";
            return;
        }

        if (!authenticated) {
            error = "Please authenticate with Internet Identity before creating a short URL.";
            return;
        }

        if (customSlug.trim() && !customSlugPattern.test(customSlug.trim())) {
            error =
                "Custom short codes can use only letters, numbers, hyphens, and underscores.";
            return;
        }

        error = "";
        pendingRequest = {
            originalUrl: newUrl.trim(),
            customSlug: customSlug.trim() || null
        };
        showPurchaseModal = true;
    }

    function cancelPurchase() {
        showPurchaseModal = false;
        pendingRequest = null;
    }

    async function confirmPurchase() {
        if (!pendingRequest) {
            showPurchaseModal = false;
            return;
        }

        loading = true;
        error = "";

        try {
            const latestWallet = await UrlApi.getWalletInfo();
            wallet = latestWallet;

            if (latestWallet.balanceE8s < latestWallet.tinyUrlPriceE8s + latestWallet.transferFeeE8s) {
                throw new Error(
                    `You need at least ${formatIcp(latestWallet.tinyUrlPriceE8s + latestWallet.transferFeeE8s)} ICP in your in-app wallet to cover the 1.0 ICP purchase and ledger fee.`
                );
            }

            const shortenedUrl = await UrlApi.createShortUrl(
                pendingRequest.originalUrl,
                pendingRequest.customSlug
            );
            const hydratedUrl = await maybeHydratePreview(shortenedUrl);
            urls = [hydratedUrl, ...urls];
            newUrl = "";
            customSlug = "";
            showPurchaseModal = false;
            pendingRequest = null;
            await loadWallet();

            const shortCode = hydratedUrl.shortCode;
            const fullShortUrl = getPublicShortUrl(shortCode);
            showSuccess(`[>] Short URL created: ${fullShortUrl}`);
        } catch (err) {
            error = "Failed to shorten URL: " + err.message;
            console.error("Error shortening URL:", err);
        } finally {
            loading = false;
        }
    }

    async function deleteUrl(id) {
        const urlItem = urls.find((u) => u.id === id);
        if (
            !confirm(
                `Are you sure you want to delete the short URL "${urlItem?.shortCode || "this URL"}"?`
            )
        )
            return;

        loading = true;
        error = "";
        try {
            await UrlApi.deleteUrl(id);
            urls = urls.filter((url) => url.id !== id);
            showSuccess(`Short URL deleted successfully`);
        } catch (err) {
            error = "Failed to delete URL: " + err.message;
            console.error("Error deleting URL:", err);
        } finally {
            loading = false;
        }
    }

    async function refreshUrlPreview(id) {
        refreshingPreviewIds = [...refreshingPreviewIds, id];
        error = "";

        try {
            const refreshedUrl = await refreshUrlPreviewWithFallback(id);
            urls = urls.map((url) => (url.id === id ? refreshedUrl : url));
            showSuccess(`Preview refreshed for /${refreshedUrl.shortCode}`);
        } catch (err) {
            error = "Failed to refresh preview metadata: " + err.message;
            console.error("Error refreshing preview metadata:", err);
        } finally {
            refreshingPreviewIds = refreshingPreviewIds.filter(
                (refreshingId) => refreshingId !== id
            );
        }
    }

    async function maybeHydratePreview(url) {
        if (!url || getPreviewStatus(url) !== "missing") {
            return url;
        }

        try {
            return await syncPreviewViaBrowser(url);
        } catch (previewError) {
            console.warn("Browser preview hydration failed:", previewError);
            return url;
        }
    }

    async function refreshUrlPreviewWithFallback(id) {
        const existingUrl = urls.find((url) => url.id === id);

        try {
            return await UrlApi.refreshUrlMetadata(id);
        } catch (backendError) {
            if (!existingUrl) {
                throw backendError;
            }

            try {
                return await syncPreviewViaBrowser(existingUrl);
            } catch (browserError) {
                throw new Error(
                    `${backendError.message} Browser fallback also failed: ${browserError.message}`
                );
            }
        }
    }

    async function syncPreviewViaBrowser(url) {
        const metadata = await UrlApi.harvestMetadataInBrowser(url.originalUrl);
        return await UrlApi.saveUrlMetadata(url.id, metadata);
    }

    function getPublicShortUrl(shortCode) {
        return `${getBackendBaseUrl(false)}/s/${shortCode}`;
    }

    function hasText(value) {
        return typeof value === "string" && value.trim().length > 0;
    }

    function getPreviewStatus(url) {
        const metadata = url.metadata;
        if (!metadata) {
            return "missing";
        }

        const hasTextMetadata =
            hasText(metadata.title) ||
            hasText(metadata.description) ||
            hasText(metadata.siteName) ||
            hasText(metadata.canonicalUrl);

        if (!hasTextMetadata) {
            return "missing";
        }

        return hasText(metadata.imageUrl) ? "ready" : "partial";
    }

    function getPreviewStatusLabel(url) {
        const status = getPreviewStatus(url);

        if (status === "ready") {
            return "Preview ready";
        }

        if (status === "partial") {
            return "Preview missing image";
        }

        return "Preview missing metadata";
    }

    function isRefreshingPreview(id) {
        return refreshingPreviewIds.includes(id);
    }

    function copyWithExecCommand(text) {
        const textArea = document.createElement("textarea");
        textArea.value = text;
        textArea.setAttribute("readonly", "");
        textArea.style.position = "fixed";
        textArea.style.opacity = "0";
        textArea.style.pointerEvents = "none";
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        textArea.setSelectionRange(0, text.length);

        try {
            return document.execCommand("copy");
        } finally {
            document.body.removeChild(textArea);
        }
    }

    async function copyToClipboard(text) {
        error = "";

        try {
            if (!copyWithExecCommand(text)) {
                if (navigator.clipboard?.writeText) {
                    await navigator.clipboard.writeText(text);
                } else {
                    throw new Error("execCommand copy failed");
                }
            }
        } catch (clipboardError) {
            if (!copyWithExecCommand(text)) {
                console.error("Clipboard copy failed:", clipboardError);
                error = "Failed to copy to clipboard. Please copy it manually.";
                return;
            }
        }

        copiedShortUrl = text;
        copiedWalletValue = text;
        showSuccess(`[C] Copied to clipboard: ${text}`);
        setTimeout(() => {
            copiedShortUrl = "";
            copiedWalletValue = "";
        }, 2000);
    }

    function openUrl(url) {
        window.open(url, "_blank");
    }

    function handleKeydown(event) {
        if (event.key === "Escape") {
            newUrl = "";
            customSlug = "";
            clearError();
        }
        if (authenticated && (event.ctrlKey || event.metaKey) && event.key === "r") {
            event.preventDefault();
            loadUrls();
        }
    }

    function clearError() {
        error = "";
    }

    function showSuccess(message) {
        successMessage = message;
        setTimeout(() => {
            successMessage = "";
        }, 3000);
    }

    function clearSuccess() {
        successMessage = "";
    }

    async function withdrawFromWallet() {
        if (!wallet) {
            error = "Load your wallet before withdrawing ICP.";
            return;
        }

        const destinationAccountId = withdrawalAccountId.trim();
        const amountIcp = Number(withdrawalAmountIcp);

        if (!destinationAccountId) {
            error = "Enter a destination account ID to withdraw ICP.";
            return;
        }

        if (!Number.isFinite(amountIcp) || amountIcp <= 0) {
            error = "Enter a valid ICP amount greater than zero.";
            return;
        }

        const amountE8s = Math.round(amountIcp * 100_000_000);
        const totalDebitE8s = amountE8s + wallet.transferFeeE8s;
        if (wallet.balanceE8s < totalDebitE8s) {
            error = `You need at least ${formatIcp(totalDebitE8s)} ICP in your in-app wallet to cover this withdrawal and the ledger fee.`;
            return;
        }

        loading = true;
        error = "";
        try {
            await UrlApi.withdrawFromWallet(destinationAccountId, amountE8s);
            withdrawalAccountId = "";
            withdrawalAmountIcp = "";
            await loadWallet();
            showSuccess(`Withdrawn ${formatIcp(amountE8s)} ICP from your in-app wallet.`);
        } catch (err) {
            error = "Failed to withdraw ICP: " + err.message;
            console.error("Error withdrawing ICP:", err);
        } finally {
            loading = false;
        }
    }

    $: purchasePriceIcp = wallet
        ? formatIcp(wallet.tinyUrlPriceE8s)
        : formatIcp(100_000_000);
    $: ledgerFeeIcp = wallet
        ? formatIcp(wallet.transferFeeE8s)
        : formatIcp(10_000);
    $: totalRequiredIcp = wallet
        ? formatIcp(wallet.tinyUrlPriceE8s + wallet.transferFeeE8s)
        : formatIcp(100_010_000);

    function formatDate(timestamp) {
        const milliseconds = Math.floor(timestamp / 1000000);
        return new Date(milliseconds).toLocaleString();
    }

    function isValidUrl(string) {
        try {
            new URL(string);
            return true;
        } catch {
            return false;
        }
    }

    onMount(() => {
        syncAuthState();
        document.addEventListener("keydown", handleKeydown);

        return () => {
            document.removeEventListener("keydown", handleKeydown);
        };
    });
</script>

<main>
    <div class="header">
        <h1>Tiny ICP</h1>
        <p>
            Shorten URLs with HTTP-native features using <a
                href="https://mops.one/liminal"
                target="_blank">Liminal HTTP framework</a
            > for Motoko
        </p>
    </div>

    {#if error}
        <div class="error-message">
            <span>[!] {error}</span>
            <button class="close-error" on:click={clearError} type="button"
                >×</button
            >
        </div>
    {/if}

    {#if successMessage}
        <div class="success-message">
            <span>[OK] {successMessage}</span>
            <button class="close-success" on:click={clearSuccess} type="button"
                >×</button
            >
        </div>
    {/if}

    {#if authLoading && !authenticated}
        <section class="auth-shell">
            <div class="auth-card">
                <h2>Authenticating...</h2>
                <p>Checking Internet Identity session.</p>
            </div>
        </section>
    {:else if !authenticated}
        <section class="auth-shell">
            <div class="auth-card">
                <p class="auth-kicker">Secure personal URL dashboard</p>
                <h2>Sign in to view your Tiny URLs</h2>
                <p>
                    Authenticate with Internet Identity to access only the short
                    links you created in Tiny ICP.
                </p>
                <button
                    class="shorten-btn auth-btn"
                    type="button"
                    on:click={handleLogin}
                    disabled={authLoading}
                >
                    {authLoading ? "Connecting..." : "[>] Login with Internet Identity"}
                </button>
                <p class="auth-footnote">
                    After signing in, this screen disappears and your personal
                    dashboard loads automatically.
                </p>
            </div>
        </section>
    {:else}
        <section class="app-shell">
            <div class="session-bar">
                <div>
                    <strong>Authenticated principal:</strong>
                    <code>{principal}</code>
                </div>
                <button class="refresh-btn" type="button" on:click={handleLogout}
                    >Sign out</button
                >
            </div>

            <div class="wallet-section">
                <div class="section-header">
                    <h2>In-App ICP Wallet</h2>
                    <button
                        on:click={loadWallet}
                        disabled={walletLoading}
                        class="refresh-btn"
                    >
                        {walletLoading ? "Refreshing..." : "Refresh Wallet"}
                    </button>
                </div>
                <p class="wallet-help">
                    Your Tiny ICP wallet shows your available balance, deposit
                    account ID, and withdrawal tools for your authenticated
                    identity.
                </p>
                {#if walletLoading && !wallet}
                    <div class="wallet-status">Loading your wallet details...</div>
                {:else if wallet}
                    <div class="wallet-grid">
                        <div class="wallet-card">
                            <span class="wallet-label">Available balance</span>
                            <strong>{formatIcp(wallet.balanceE8s)} ICP</strong>
                            <small>
                                Deposit ICP into your account ID below to fund
                                this wallet.
                            </small>
                        </div>
                        <div class="wallet-card full">
                            <span class="wallet-label">Deposit account ID</span>
                            <code>{wallet.depositAccountId}</code>
                            <small>
                                Send ICP to this account ID to fund your Tiny ICP
                                wallet balance.
                            </small>
                            <button
                                class="copy-btn small"
                                class:copied={copiedWalletValue === wallet.depositAccountId}
                                on:click={() => copyToClipboard(wallet.depositAccountId)}
                            >
                                {copiedWalletValue === wallet.depositAccountId
                                    ? "Copied ✓"
                                    : "Copy Account ID"}
                            </button>
                        </div>
                    </div>

                    <div class="wallet-withdraw">
                        <h3>Transfer ICP out of your wallet</h3>
                        <div class="withdraw-grid">
                            <div class="form-field">
                                <label for="withdraw-account" class="form-label">Destination Account ID</label>
                                <input
                                    id="withdraw-account"
                                    type="text"
                                    bind:value={withdrawalAccountId}
                                    placeholder="Enter 64-character account ID"
                                    disabled={loading}
                                    class="form-input"
                                />
                            </div>
                            <div class="form-field">
                                <label for="withdraw-amount" class="form-label">Amount (ICP)</label>
                                <input
                                    id="withdraw-amount"
                                    type="number"
                                    min="0.0001"
                                    step="0.0001"
                                    bind:value={withdrawalAmountIcp}
                                    placeholder="0.2500"
                                    disabled={loading}
                                    class="form-input"
                                />
                            </div>
                        </div>
                        <div class="action-row wallet-actions">
                            <small class="wallet-help">
                                Withdrawals are sent from your derived in-app wallet subaccount and include the standard {ledgerFeeIcp} ICP ledger fee.
                            </small>
                            <button type="button" class="refresh-btn" on:click={withdrawFromWallet} disabled={loading}>
                                {loading ? "Sending..." : "Transfer ICP Out"}
                            </button>
                        </div>
                    </div>
                {:else}
                    <div class="wallet-status warning">
                        <strong>Wallet unavailable.</strong>
                        <div>{walletError || "We could not load your wallet details yet."}</div>
                        <small>Use Refresh Wallet to try again.</small>
                    </div>
                {/if}
            </div>

            <div class="shorten-section">
                <form on:submit|preventDefault={shortenUrl} class="shorten-form">
                    <div class="form-field">
                        <label for="new-url" class="form-label">Long URL</label>
                        <input
                            id="new-url"
                            type="url"
                            bind:value={newUrl}
                            placeholder="https://example.com/very/long/url..."
                            disabled={loading}
                            required
                            class="form-input url-input"
                        />
                    </div>

                    <div class="form-field">
                        <label for="custom-slug" class="form-label"
                            >Custom Short Code (Optional)</label
                        >
                        <input
                            id="custom-slug"
                            type="text"
                            bind:value={customSlug}
                            placeholder="my-link"
                            disabled={loading}
                            maxlength="20"
                            class="form-input"
                        />
                        <small class="form-help"
                            >Letters, numbers, hyphens, and underscores only</small
                        >
                    </div>

                    <div class="action-row">
                        <button
                            type="submit"
                            disabled={loading || !newUrl.trim() || !isValidUrl(newUrl)}
                            class="shorten-btn"
                        >
                            {loading ? "Shortening..." : "[>] Shorten URL"}
                        </button>
                    </div>
                    <p class="form-help preview-note">
                        New short URLs are created only through the authenticated
                        wallet flow, and each purchase now captures destination
                        page metadata for sharing previews.
                    </p>
                </form>
            </div>


            {#if showPurchaseModal}
                <div class="modal-backdrop" role="presentation">
                    <div
                        class="confirm-modal"
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="purchase-modal-title"
                    >
                        <p class="auth-kicker">Purchase confirmation</p>
                        <h2 id="purchase-modal-title">Confirm Tiny URL purchase</h2>
                        <p>
                            Creating this short URL will transfer <strong>{purchasePriceIcp} ICP</strong>
                            from your in-app wallet to the Tiny ICP payment account before the link is created.
                        </p>
                        <div class="wallet-status">
                            <div><strong>Long URL:</strong> {pendingRequest?.originalUrl}</div>
                            <div>
                                <strong>Custom short code:</strong>
                                {pendingRequest?.customSlug || "Auto-generate one for me"}
                            </div>
                            <div><strong>Price:</strong> {purchasePriceIcp} ICP</div>
                            <div><strong>Ledger fee:</strong> {ledgerFeeIcp} ICP</div>
                            <div><strong>Wallet balance:</strong> {wallet ? `${formatIcp(wallet.balanceE8s)} ICP` : "Loading..."}</div>
                            <div><strong>Needed to proceed:</strong> {totalRequiredIcp} ICP</div>
                        </div>
                        <div class="action-row modal-actions">
                            <button type="button" class="refresh-btn" on:click={cancelPurchase} disabled={loading}>
                                Cancel
                            </button>
                            <button type="button" class="shorten-btn" on:click={confirmPurchase} disabled={loading}>
                                {loading ? "Processing payment..." : `Confirm & Pay ${purchasePriceIcp} ICP`}
                            </button>
                        </div>
                    </div>
                </div>
            {/if}

            <div class="urls-section">
                <div class="section-header">
                    <h2>Your Short URLs ({urls.length})</h2>
                    <button on:click={loadUrls} disabled={loading} class="refresh-btn">
                        {loading ? "[...] Loading..." : "Refresh"}
                    </button>
                </div>

                {#if loading && urls.length === 0}
                    <div class="loading">Loading URLs...</div>
                {:else if urls.length === 0}
                    <div class="empty-state">
                        <div class="empty-icon">⌁</div>
                        <p>No short URLs yet. Create your first one above!</p>
                    </div>
                {:else}
                    <div class="urls-grid">
                        {#each urls as url (url.id)}
                            <div class="url-card">
                                <div class="url-info">
                                    <div class="url-header">
                                        <h3 class="short-code">/{url.shortCode}</h3>
                                        <div class="url-actions">
                                            <button
                                                class="copy-btn small"
                                                class:copied={copiedShortUrl ===
                                                    getPublicShortUrl(url.shortCode)}
                                                on:click={() =>
                                                    copyToClipboard(
                                                        getPublicShortUrl(url.shortCode)
                                                    )}
                                            >
                                                {copiedShortUrl ===
                                                getPublicShortUrl(url.shortCode)
                                                    ? "Copied ✓"
                                                    : "Copy Url"}
                                            </button>
                                            <button
                                                class="visit-btn"
                                                on:click={() =>
                                                    openUrl(getPublicShortUrl(url.shortCode))}
                                            >
                                                ↗
                                            </button>
                                            <button
                                                on:click={() => deleteUrl(url.id)}
                                                disabled={loading}
                                                class="delete-btn"
                                            >
                                                X
                                            </button>
                                        </div>
                                    </div>

                                    <div class="url-details">
                                        <p class="short-url">
                                            <strong>Short:</strong>
                                            <a
                                                href={getPublicShortUrl(url.shortCode)}
                                                target="_blank"
                                                rel="noopener"
                                            >
                                                {getPublicShortUrl(url.shortCode)}
                                            </a>
                                        </p>
                                        <p class="original-url">
                                            <strong>Original:</strong>
                                            <a
                                                href={url.originalUrl}
                                                target="_blank"
                                                rel="noopener"
                                                class="original-link"
                                            >
                                                {url.originalUrl}
                                            </a>
                                        </p>
                                        <div class="url-stats">
                                            <span class="stat">[HITS] {url.clicks || 0} clicks</span>
                                            <span class="stat">[DATE] {formatDate(url.createdAt)}</span>
                                        </div>
                                        <div class="preview-panel">
                                            <div class="preview-panel-header">
                                                <span
                                                    class={`preview-badge ${getPreviewStatus(
                                                        url
                                                    )}`}
                                                    >{getPreviewStatusLabel(url)}</span
                                                >
                                                <button
                                                    type="button"
                                                    class="refresh-btn preview-refresh-btn"
                                                    on:click={() =>
                                                        refreshUrlPreview(url.id)}
                                                    disabled={loading ||
                                                        isRefreshingPreview(url.id)}
                                                >
                                                    {isRefreshingPreview(url.id)
                                                        ? "Refreshing..."
                                                        : "Refresh Preview"}
                                                </button>
                                            </div>
                                            {#if url.metadata}
                                                {#if url.metadata.title}
                                                    <p class="preview-meta">
                                                        <strong>Title:</strong>
                                                        {url.metadata.title}
                                                    </p>
                                                {/if}
                                                {#if url.metadata.description}
                                                    <p class="preview-meta">
                                                        <strong>Description:</strong>
                                                        {url.metadata.description}
                                                    </p>
                                                {/if}
                                                {#if url.metadata.imageUrl}
                                                    <p class="preview-meta">
                                                        <strong>Image:</strong>
                                                        <a
                                                            href={url.metadata.imageUrl}
                                                            target="_blank"
                                                            rel="noopener"
                                                        >
                                                            {url.metadata.imageUrl}
                                                        </a>
                                                    </p>
                                                {/if}
                                            {/if}
                                        </div>
                                    </div>
                                </div>
                            </div>
                        {/each}
                    </div>
                {/if}
            </div>
        </section>
    {/if}
</main>
