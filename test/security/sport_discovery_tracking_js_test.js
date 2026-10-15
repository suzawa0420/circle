const assert = require('assert');
const vm = require('vm');
const fs = require('fs');
const listeners = {};
let marker;
const context = {window: {}, document: {
  addEventListener(name, fn) { assert(!listeners[name]); listeners[name] = fn; },
  querySelectorAll() { return marker ? [marker] : []; }
}};
const source = fs.readFileSync('app/assets/javascripts/sport_discovery_tracking.js', 'utf8');
vm.runInNewContext(source, context);
vm.runInNewContext(source, context);
listeners.click({target: {closest() {return {dataset: {sportListingClick: 'soft-tennis'}};}}});
marker = {dataset: {sportInquiryDelivered: 'ski'}, remove() {marker = null;}};
listeners['turbolinks:load']();
listeners.DOMContentLoaded();
listeners.click({target: {closest() {return {dataset: {sportListingClick: 'unsafe/user-input'}};}}});
assert.deepStrictEqual(JSON.parse(JSON.stringify(context.window.dataLayer)), [
  {event: 'sport_listing_click', sport: 'soft-tennis'},
  {event: 'sport_inquiry_delivered', sport: 'ski'}
]);
console.log('Sports tracking: duplicate binding, delivered marker consumption, and minimal payload passed');
