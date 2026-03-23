<script>
	import { browser } from "$app/environment";
	import { page } from "$app/stores";
	import { onMount } from "svelte";

	const contactId = "contact-15";
	const contactOrigin = "https://thowo-iqaaa-aaaab-ac3wa-cai.icp0.io";
	const iconColor = "#91ff24";
	let isMobile = false;
	let isOpen = false;
	let iframeSrc = "";

	$: isShortLinkRoute = $page.url.pathname.startsWith("/s/");
	$: if (isShortLinkRoute) {
		isOpen = false;
	}
	$: if (browser && !isShortLinkRoute) {
		const embedUrl = encodeURIComponent(window.location.href);
		const embedOrigin = encodeURIComponent(window.location.origin);
		iframeSrc =
			`${contactOrigin}/embed.html?id=${encodeURIComponent(contactId)}` +
			`&embed_url=${embedUrl}&embed_origin=${embedOrigin}#/contact-popup`;
	} else {
		iframeSrc = "";
	}

	function updateViewportState() {
		isMobile = window.matchMedia("(max-width: 640px)").matches;
	}

	function togglePopup() {
		isOpen = !isOpen;
	}

	function closePopup() {
		isOpen = false;
	}

	function handleKeydown(event) {
		if (event.key === "Escape") {
			closePopup();
		}
	}

	onMount(() => {
		updateViewportState();
		window.addEventListener("resize", updateViewportState);
		window.addEventListener("keydown", handleKeydown);

		return () => {
			window.removeEventListener("resize", updateViewportState);
			window.removeEventListener("keydown", handleKeydown);
		};
	});
</script>

{#if browser && !isShortLinkRoute}
	<button
		type="button"
		class="contact-widget-toggle"
		class:open={isOpen}
		aria-label="Open contact form"
		aria-expanded={isOpen}
		on:click={togglePopup}
		style={`--contact-widget-color: ${iconColor};`}
	>
		<svg
			xmlns="http://www.w3.org/2000/svg"
			width="28"
			height="28"
			viewBox="0 0 24 24"
			fill="none"
			stroke="#ffffff"
			stroke-width="2.25"
			stroke-linecap="round"
			stroke-linejoin="round"
			aria-hidden="true"
			focusable="false"
		>
			<rect x="2" y="4" width="20" height="16" rx="2" />
			<path d="M22 7L12 13L2 7" />
		</svg>
	</button>

	{#if isOpen && iframeSrc}
		<div
			class="contact-widget-overlay"
			aria-hidden="true"
			on:click={closePopup}
		></div>
		<div
			class="contact-widget-popup"
			class:mobile={isMobile}
			role="dialog"
			aria-modal="true"
			aria-label="Contact form"
		>
			<button
				type="button"
				class="contact-widget-close"
				aria-label="Close contact form"
				on:click={closePopup}
			>
				×
			</button>
			<iframe
				title="TinyICP contact form"
				src={iframeSrc}
				loading="lazy"
			></iframe>
		</div>
	{/if}
{/if}

<style>
	.contact-widget-toggle {
		position: fixed;
		right: 24px;
		bottom: calc(24px + env(safe-area-inset-bottom, 0px));
		width: 56px;
		height: 56px;
		border: none;
		border-radius: 999px;
		background: var(--contact-widget-color, #91ff24);
		color: #ffffff;
		display: flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		box-shadow: 0 12px 30px rgba(15, 23, 42, 0.24);
		opacity: 0.9;
		transition: transform 120ms ease, opacity 120ms ease;
		z-index: 1400;
	}

	.contact-widget-toggle:hover,
	.contact-widget-toggle.open {
		opacity: 1;
		transform: translateY(-2px);
	}

	.contact-widget-overlay {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.45);
		z-index: 1398;
	}

	.contact-widget-popup {
		position: fixed;
		right: 24px;
		bottom: calc(96px + env(safe-area-inset-bottom, 0px));
		width: min(360px, calc(100vw - 48px));
		height: min(620px, calc(100vh - 160px));
		background: #ffffff;
		border-radius: 16px;
		box-shadow: 0 20px 50px rgba(15, 23, 42, 0.28);
		overflow: hidden;
		z-index: 1399;
	}

	.contact-widget-popup.mobile {
		right: 12px;
		bottom: calc(92px + env(safe-area-inset-bottom, 0px));
		width: calc(100vw - 24px);
		height: min(600px, 78vh);
	}

	.contact-widget-popup iframe {
		width: 100%;
		height: 100%;
		border: none;
		display: block;
		background: #ffffff;
	}

	.contact-widget-close {
		position: absolute;
		top: 8px;
		right: 12px;
		width: 28px;
		height: 28px;
		border: none;
		border-radius: 999px;
		background: #0f172a;
		color: #ffffff;
		font-size: 1.1rem;
		line-height: 1;
		cursor: pointer;
		z-index: 1;
	}

	@media (max-width: 640px) {
		.contact-widget-toggle {
			right: 12px;
			bottom: calc(16px + env(safe-area-inset-bottom, 0px));
		}
	}
</style>
