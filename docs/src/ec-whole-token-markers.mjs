/**
 * Expressive Code plugin: make plain-string text markers match whole tokens.
 *
 * Expressive Code resolves a string marker definition with `lineText.indexOf`
 * (`plugin-text-markers`, `getInlineSearchTermMatches`), so it highlights every
 * substring occurrence. A fence annotated `"den"` therefore also highlights the
 * `den` inside `denful`, and the author gets extra highlights they never asked
 * for — silently, since nothing in the source hints at it.
 *
 * The same function has a second branch for `RegExp` definitions, so converting
 * each string to an equivalent boundary-anchored `RegExp` routes it through
 * matching that respects token edges, without touching any content.
 *
 * Boundaries are added only on edges that are word characters: a marker written
 * as `".mainModule"` or `"-b"` is deliberately anchored to punctuation, and
 * `\b` there would mean the opposite of what the author wrote.
 */

const MARKER_PROPS = ['mark', 'ins', 'del'];
const WORD_EDGE = /[A-Za-z0-9_]/;

const escapeRegExp = (literal) => literal.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * @param {string} literal
 * @returns {string | RegExp} the original literal when no edge can carry a
 * boundary, otherwise a global, capture-group-free RegExp. Both are required by
 * the consuming branch: it calls `matchAll` (needs `g`) and prefers capture
 * groups over the full match when any are present.
 */
function toWholeTokenMatcher(literal) {
  if (!literal) return literal;
  const lead = WORD_EDGE.test(literal[0]) ? '\\b' : '';
  const trail = WORD_EDGE.test(literal[literal.length - 1]) ? '\\b' : '';
  if (!lead && !trail) return literal;
  return new RegExp(`${lead}${escapeRegExp(literal)}${trail}`, 'g');
}

export function wholeTokenTextMarkers() {
  return {
    name: 'whole-token-text-markers',
    hooks: {
      /*
       * `preprocessCode` runs after every plugin's `preprocessMetadata`, so the
       * text-markers plugin has already parsed the fence meta into props, and
       * before `annotateCode`, where the matching happens.
       */
      preprocessCode: ({ codeBlock }) => {
        for (const prop of MARKER_PROPS) {
          const value = codeBlock.props[prop];
          if (value === undefined) continue;
          const definitions = Array.isArray(value) ? value : [value];
          codeBlock.props[prop] = definitions.map((definition) =>
            typeof definition === 'string' ? toWholeTokenMatcher(definition) : definition
          );
        }
      },
    },
  };
}
