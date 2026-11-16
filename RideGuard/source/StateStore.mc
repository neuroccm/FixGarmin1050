import Toybox.Application;
import Toybox.Lang;

// The small persisted ride record. Only RideGuardField.compute() calls save().
module StateStore {
    const KEY = "st";

    // Several field instances can run at once: an open ride already stored keeps its earlier rideStart.
    function merge(stored as Dictionary or Null, observed as Dictionary) as Dictionary {
        var out = {} as Dictionary;
        var keys = observed.keys();
        for (var i = 0; i < keys.size(); i++) { out.put(keys[i], observed.get(keys[i])); }
        if (stored != null && stored.get("rideOpen") == true && observed.get("rideOpen") == true) {
            var a = stored.get("rideStart");
            var b = observed.get("rideStart");
            if (a != null && (b == null || (a as Number) < (b as Number))) { out.put("rideStart", a); }
        }
        return out;
    }

    function load() as Dictionary or Null {
        var v = Application.Storage.getValue(KEY);
        return (v instanceof Dictionary) ? v as Dictionary : null;
    }

    function save(observed as Dictionary) as Void {
        try {
            Application.Storage.setValue(KEY, merge(load(), observed));
        } catch (e) {
            EventLog.write("STORE-ERR");
        }
    }
}
