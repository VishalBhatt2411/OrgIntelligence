/**
 * Purpose: Opaque-cursor page of keys returned by getCurrentKeysByType (GraphRepository.md §2, §13).
 * Responsibilities: Carry one page of keyset-paginated results plus continuation state.
 * Dependencies: None.
 * Limitations: cursor format is opaque — callers never parse it, only pass it back.
 */
public class OI_KeysPage {
    public final List<String> items;
    public final String nextCursor;
    public final Boolean hasMore;

    public OI_KeysPage(List<String> items, String nextCursor, Boolean hasMore) {
        this.items = items == null ? new List<String>() : items;
        this.nextCursor = nextCursor;
        this.hasMore = hasMore == null ? false : hasMore;
    }
}
