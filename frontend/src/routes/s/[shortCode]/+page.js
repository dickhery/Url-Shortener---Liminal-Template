export const prerender = false;
import { redirect } from '@sveltejs/kit';
import UrlApi from '$lib/urlApi.js';

export const load = async ({ params }) => {
  throw redirect(302, UrlApi.getShortUrl(params.shortCode));
};
