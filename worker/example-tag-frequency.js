/* For each piece of content there are a few
 * variables you have access to.
 * You can get to them using requirejs define:
 *
 * - state : object you update that stores results
 * - $root : jQuery root element of the document
 * - metadata : has things like roles, title, etc
 * - resources : Info on the resources like
 *               mime/type and file size
 *
 */
define(['state', '$root'], function(state, $root) {

/* This example finds the frequency of elements
 * in a piece of content */
$root.find('content *').each(function(i, el) {
  var tag = el.tagName.toLowerCase();
  /* Remove the namespace prefix */
  tag = tag.split(':');
  tag = tag[tag.length-1];

  /* Update the state after analyzing this
   * piece of content */
  state[tag] = state[tag] || 0; /* Init if null */
  state[tag] += 1;
});

}) /* End requirejs define */
