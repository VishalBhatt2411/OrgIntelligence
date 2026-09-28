/**
 * Purpose: Finds which component names ("needles") occur as substrings of a source text.
 * Responsibilities: Equivalent to running `text.contains(needle)` for every needle, but in
 *                    roughly O(text) instead of O(text × needles): a needle made only of word
 *                    characters can only occur inside a single word token, so each token's
 *                    substrings of the needle lengths are looked up in a Set. Needles containing
 *                    other characters (e.g. workflow rule names with spaces) fall back to contains.
 * Dependencies: None.
 * Limitations: Matching is case-sensitive, exactly like the substring search it replaces.
 *              One instance per transaction — its token cache is not meant to be serialized.
 */
public with sharing class OI_TD_UsageMatcher {
  private static final Pattern WORD_ONLY = Pattern.compile('^[A-Za-z0-9_]+$');
  private static final Integer TOKEN_CACHE_LIMIT = 20000;
  private static final List<String> NO_MATCH = new List<String>();

  private Set<String> needles = new Set<String>();
  private List<Integer> lengths = new List<Integer>();
  private List<String> nonWordNeedles = new List<String>();
  private Map<String, List<String>> tokenCache = new Map<String, List<String>>();

  public OI_TD_UsageMatcher(Set<String> allNeedles) {
    Set<Integer> lengthSet = new Set<Integer>();
    for (String needle : allNeedles) {
      if (String.isEmpty(needle)) {
        continue;
      }
      if (WORD_ONLY.matcher(needle).matches()) {
        needles.add(needle);
        lengthSet.add(needle.length());
      } else {
        nonWordNeedles.add(needle);
      }
    }
    lengths.addAll(lengthSet);
    lengths.sort();
  }

  /** Every needle that occurs somewhere in text. */
  public Set<String> match(String text) {
    Set<String> found = new Set<String>();
    if (String.isEmpty(text)) {
      return found;
    }
    if (!needles.isEmpty()) {
      for (String token : tokenize(text)) {
        if (token.length() == 0) {
          continue;
        }
        List<String> hits = tokenCache.get(token);
        if (hits == null) {
          hits = scanToken(token);
          if (tokenCache.size() < TOKEN_CACHE_LIMIT) {
            tokenCache.put(token, hits);
          }
        }
        if (!hits.isEmpty()) {
          found.addAll(hits);
        }
      }
    }
    for (String needle : nonWordNeedles) {
      if (text.contains(needle)) {
        found.add(needle);
      }
    }
    return found;
  }

  private List<String> tokenize(String text) {
    try {
      return text.split('[^A-Za-z0-9_]+');
    } catch (Exception e) {
      // Very large inputs can exceed the regex engine's limits in one pass; per line is equivalent.
      List<String> tokens = new List<String>();
      for (String line : text.split('\n')) {
        tokens.addAll(line.split('[^A-Za-z0-9_]+'));
      }
      return tokens;
    }
  }

  private List<String> scanToken(String token) {
    Integer len = token.length();
    Set<String> hits = null;
    for (Integer needleLength : lengths) {
      if (needleLength > len) {
        break;
      }
      for (Integer i = 0; i + needleLength <= len; i++) {
        String candidate = token.substring(i, i + needleLength);
        if (needles.contains(candidate)) {
          if (hits == null) {
            hits = new Set<String>();
          }
          hits.add(candidate);
        }
      }
    }
    return hits == null ? NO_MATCH : new List<String>(hits);
  }
}
