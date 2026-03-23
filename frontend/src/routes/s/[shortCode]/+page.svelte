<script>
  import "../../../index.scss";
  import { onMount } from "svelte";
  import UrlApi from "$lib/urlApi.js";

  export let data;

  let loading = true;
  let redirectingViaFallback = false;
  let redirectUrl = UrlApi.getBackendShortUrl(data.shortCode);
  let title = `TinyICP Short Link - ${data.shortCode}`;
  let description = "Shared via TinyICP.";
  let siteName = "TinyICP";
  let error = "";
  let inactiveMessage = "";

  const removeLoadingShell = () => {
    document.getElementById("redirect-loading-shell")?.remove();
  };

  const scheduleRedirect = (url, delay = 300) => {
    window.setTimeout(() => {
      window.location.replace(url);
    }, delay);
  };

  onMount(() => {
    let cancelled = false;

    const startRedirect = async () => {
      removeLoadingShell();

      try {
        const url = await UrlApi.recordShortLinkVisit(data.shortCode);
        if (!url) {
          redirectingViaFallback = true;
          scheduleRedirect(UrlApi.getBackendShortUrl(data.shortCode), 150);
          return;
        }

        redirectUrl = url.originalUrl;
        title = url.metadata?.title || title;
        description = url.metadata?.description || description;
        siteName = url.metadata?.siteName || siteName;

        if (!cancelled) {
          loading = false;
        }

        scheduleRedirect(url.originalUrl);
      } catch (redirectError) {
        if (
          redirectError.message?.includes("prepaid click allowance has run out") ||
          redirectError.message?.includes("paused")
        ) {
          inactiveMessage = redirectError.message;
          redirectUrl = UrlApi.getPublicShortUrl(data.shortCode);
          title = `TinyICP Link Paused - ${data.shortCode}`;
          description =
            "This short URL is inactive because its prepaid click allowance has been exhausted.";

          try {
            const url = await UrlApi.getPublicUrl(data.shortCode);
            if (url?.metadata?.siteName) {
              siteName = url.metadata.siteName;
            }
          } catch (lookupError) {
            console.warn("Failed to load paused short URL details:", lookupError);
          }

          if (!cancelled) {
            loading = false;
          }
          return;
        }

        error = redirectError.message;
        redirectingViaFallback = true;
        if (!cancelled) {
          loading = false;
        }
        scheduleRedirect(UrlApi.getBackendShortUrl(data.shortCode), 300);
      }
    };

    startRedirect();

    return () => {
      cancelled = true;
    };
  });
</script>

<svelte:head>
  <title>{title}</title>
  <meta name="description" content={description} />
</svelte:head>

<section class="redirect-shell">
  <div class="redirect-panel">
    <p class="redirect-kicker">{siteName}</p>
    <h1>{inactiveMessage ? "This TinyICP URL is paused" : "Redirecting you to the original URL..."}</h1>
    <p class="redirect-description">
      {#if inactiveMessage}
        {inactiveMessage}
      {:else if redirectingViaFallback}
        Resolving the final destination through TinyICP.
      {:else if loading}
        Looking up the destination for this short link.
      {:else}
        You should arrive at the destination in just a moment.
      {/if}
    </p>
    <p class="redirect-url">{redirectUrl}</p>
    {#if inactiveMessage}
      <p class="redirect-help">
        The owner can reactivate this link at any time by topping it up with more clicks in the TinyICP app.
      </p>
    {:else}
      <p class="redirect-help">
        If you are not redirected automatically,
        <a href={redirectUrl} rel="noopener">click here</a>.
      </p>
    {/if}
    {#if error}
      <p class="redirect-note">Fallback redirect in progress: {error}</p>
    {:else if redirectingViaFallback}
      <p class="redirect-note">
        Using the TinyICP redirect service as a fallback.
      </p>
    {/if}
  </div>
</section>
