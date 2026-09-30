/**
 * Purpose: Everything a Tech Debt scan remembers between batch executes (carried by the
 *          Database.Stateful OI_TD_ScanBatch and handed to OI_TD_ScanEngine each execute).
 * Responsibilities: Stage/cursor bookkeeping plus the compact component inventory the analyzers
 *                    need at the end. Record classes use the short property names of the stored
 *                    JSON payloads (see OI_TD_Controller) so they serialize straight into them.
 * Dependencies: OI_TD_Rules (info classes).
 * Limitations: Kept deliberately compact — source bodies are never held here, only names, ids
 *              and flags; large text lives in OI_TD_Scan_Data__c packs.
 */
public with sharing class OI_TD_ScanState {
  public class ObjRec {
    public String a; // apiName
    public String l; // label
    public Integer c; // fieldCount
    public String i; // sfId
    public Integer s; // fields shard seq
    public List<Integer> u;
    public List<Integer> r;
  }

  public class ClassRec {
    public String n;
    public String i;
    public String c; // category label
    public Boolean b; // isBatch
    public Boolean x; // isTest
    public Boolean e; // isEntryPoint
    public List<Integer> u;
    public List<Integer> r;
  }

  public class TriggerRec {
    public String n;
    public String o;
    public String i;
    public List<Integer> u;
    public List<Integer> r;
  }

  public class FlowRec {
    public String a;
    public String l;
    public String s; // status
    public String tt; // trigger type
    public String o; // object
    public String p; // processType
    public String k; // category label
    public String i;
    public List<Integer> u;
    public List<Integer> r;
  }

  public class WfRec {
    public String n;
    public String o;
    public Boolean ac;
    public String tt;
    public String i;
    public List<Integer> u;
    public List<Integer> r;
  }

  public class LwcRec {
    public String a;
    public String i;
    public List<Integer> u;
    public List<Integer> r;
  }

  public class VfRec {
    public String n;
    public String i;
    public List<Integer> u;
    public List<Integer> r;
  }

  public class EmailRec {
    public String n;
    public String d;
    public String t;
    public Boolean ac;
    public String i;
  }

  public class PkgRec {
    public String n;
    public String ns;
    public String vn;
    public String vv;
  }

  public class HolderRec {
    public String n;
    public String t;
    public String i;
  }

  public class SectionResult {
    public String category;
    public Integer itemCount;
    public String error;
    public SectionResult(String category, Integer itemCount, String error) {
      this.category = category;
      this.itemCount = itemCount;
      this.error = error;
    }
  }

  // ---- control ----
  public Id scanId;
  public Integer stage = 0;
  public Integer phase = 0;
  public Integer cursor = 0;
  public String nextUrl;
  public List<String> work = new List<String>();
  public List<String> work2 = new List<String>();
  public List<Integer> workLens = new List<Integer>();
  public Integer sectionCount = 0;
  public Integer failStreak = 0;
  public Boolean flushRequested = false;
  public Boolean failed = false;
  public String error;
  public List<SectionResult> sections = new List<SectionResult>();

  // ---- objects & fields ----
  public List<String> targets = new List<String>();
  public Map<String, String> objIdByName = new Map<String, String>();
  public Map<String, String> objNameById = new Map<String, String>();
  public Map<String, String> fieldIdByKey = new Map<String, String>();
  public List<ObjRec> objects = new List<ObjRec>();
  public Integer shardSeq = 0;
  public Integer shardChars = 0;
  public Map<String, List<Map<String, Object>>> shard = new Map<String, List<Map<String, Object>>>();
  public Integer fieldTotal = 0;
  public Integer fieldsUsed = 0;
  public Set<String> allFieldNames = new Set<String>();
  public Set<String> noIdFieldNames = new Set<String>();
  public List<String> fieldIds = new List<String>();
  public List<String> outgoingOrder = new List<String>();
  public Map<String, List<String>> outgoingByObject = new Map<String, List<String>>();

  // ---- code & automation ----
  public List<ClassRec> classes = new List<ClassRec>();
  public List<TriggerRec> triggers = new List<TriggerRec>();
  public List<FlowRec> flows = new List<FlowRec>();
  public List<WfRec> wfs = new List<WfRec>();
  public List<LwcRec> lwcs = new List<LwcRec>();
  public List<VfRec> vfps = new List<VfRec>();
  public List<VfRec> vfcs = new List<VfRec>();
  public List<EmailRec> emails = new List<EmailRec>();
  public List<PkgRec> pkgs = new List<PkgRec>();
  public Long totalChars = 0;
  public Integer totalUnits = 0;

  // ---- haystack packs (flow definitions, LWC sources) ----
  public Integer flowPacks = 0;
  public Integer lwcPacks = 0;
  public List<List<String>> hayBuffer = new List<List<String>>();
  public Integer hayChars = 0;

  // ---- permissions & sharing ----
  public List<OI_TD_Rules.AccessHolder> holders = new List<OI_TD_Rules.AccessHolder>();
  public List<HolderRec> holderRecs = new List<HolderRec>();
  public List<OI_TD_Rules.OwdInfo> owds = new List<OI_TD_Rules.OwdInfo>();
  public List<String> ruleObjectOrder = new List<String>();
  public Map<String, Integer> ruleCounts = new Map<String, Integer>();
  public List<OI_TD_Rules.RoleInfo> roles = new List<OI_TD_Rules.RoleInfo>();

  // ---- dependency graph ----
  public List<List<String>> refs = new List<List<String>>();
  public Map<String, Integer> refIndex = new Map<String, Integer>();
  public Map<String, List<Integer>> dependentsBySfId = new Map<String, List<Integer>>();
  /** Distinct MetadataComponentIds depending on each referenced Id (the god_component count). */
  public Map<String, Set<String>> dependentIdsBySfId = new Map<String, Set<String>>();
  public Map<String, List<Integer>> referencesBySfId = new Map<String, List<Integer>>();
  public Map<String, Integer> refIdxBySfId = new Map<String, Integer>();
  public List<String> depRefOrder = new List<String>();
  public Boolean hasDep = false;
  public Integer depRows = 0;

  // ---- usage (haystack) ----
  public Set<String> needles = new Set<String>();
  public Map<String, List<Integer>> hits = new Map<String, List<Integer>>();

  // ---- findings ----
  public Map<Integer, Integer> counters = new Map<Integer, Integer>();
  public List<OI_TD_Finding__c> pendingFindings = new List<OI_TD_Finding__c>();
  public List<OI_TD_Scan_Data__c> pendingData = new List<OI_TD_Scan_Data__c>();
  public Map<String, Integer> usedCounts = new Map<String, Integer>();

  public OI_TD_ScanState(Id scanId) {
    this.scanId = scanId;
  }
}
