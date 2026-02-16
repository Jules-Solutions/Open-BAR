# Research Report 02: AngelScript Language Reference & CircuitAI API

> **Quest:** BARB
> **Session:** Session_2
> **Date:** 2026-02-13
> **Purpose:** AngelScript crash course and CircuitAI API reference, organized for modding Barb3

---

## Table of Contents

1. [AngelScript Language Crash Course](#1-angelscript-language-crash-course)
2. [CircuitAI Architecture](#2-circuitai-architecture)
3. [Key API Classes](#3-key-api-classes)
4. [Task::BuildType Enum](#4-taskbuildtype-enum)
5. [Task::Priority Enum](#5-taskpriority-enum)
6. [How Build Tasks Work in Practice](#6-how-build-tasks-work-in-practice)
7. [How to Add New Behavior](#7-how-to-add-new-behavior)
8. [Logging and Debugging](#8-logging-and-debugging)

---

## 1. AngelScript Language Crash Course

### What Is AngelScript?

AngelScript is a **statically-typed, compiled-at-load-time scripting language** designed to be embedded in C++ applications. It was created by Andreas Jonsson and is used in game engines where Lua would feel too loose and C++ would be too dangerous to expose directly. Think of it as a safer C++ subset with automatic memory management.

**Key mental model:** If you know C#, Java, or C++, you already know 90% of AngelScript syntax. The main surprises are handle references (`@`), the `!is null` idiom, and the `&in`/`&out` parameter system.

References:
- [Official AngelScript Manual](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_script.html)
- [AngelScript Overview (Openplanet)](https://openplanet.dev/docs/tutorials/angelscript-overview)

### Primitive Types

```angelscript
int x = 42;              // 32-bit signed integer
uint y = 100;            // 32-bit unsigned integer
uint8 flags = 0xFF;      // 8-bit unsigned (used for enum values in CircuitAI)
float speed = 3.14f;     // 32-bit float (the 'f' suffix is conventional)
double precise = 3.14;   // 64-bit float (rarely used in CircuitAI)
bool active = true;      // boolean
string name = "armcom";  // string (reference type, not primitive, but used everywhere)
```

**CircuitAI-specific type aliases:**
```angelscript
Id unitId = 42;           // typedef for int, used for unit IDs
Type roleType;            // typedef for mask/enum types
TypeMask roleMask;        // struct with .type and .mask fields
```

### Variables and Constants

```angelscript
// Constants (immutable after init)
const int SECOND = 30;                    // sim frames per second
const int MINUTE = 60 * SECOND;           // 1800 frames
const int SQUARE_SIZE = 8;                // map grid unit
const float NEAR_ZERO = 1e-3f;

// Mutable variables
float metalIncome = 0.0f;
bool isEnergyStalling = false;
```

From Barb3's `define.as`:
```angelscript
const int SECOND = 30;
const int MINUTE = 60 * SECOND;
const int ASSIGN_TIMEOUT = 5 * MINUTE;    // 9000 frames = 5 real minutes
const int SQUARE_SIZE = 8;
const AIFloat3 RgtVector(1.0f, 0.0f, 0.0f);
const uint LOG_LEVEL = 1;
```

### Handle References (`@`) -- THE Key Concept

This is the single most important AngelScript concept to understand. Handles are AngelScript's version of smart pointers. They use **reference counting** (not garbage collection) to manage object lifetimes.

```angelscript
// Declaring a handle variable (starts as null)
CCircuitDef@ def;

// Assigning a handle (the @ on the left means "set this handle to point at")
@def = ai.GetCircuitDef("armcom");

// Using a handle -- access members normally (no -> like C++)
string name = def.GetName();
float cost = def.costM;

// Handle in function return types
CCircuitDef@ GetSomeDef() { ... }

// Handle in function parameters
void DoSomething(CCircuitDef@ unitDef) { ... }
```

**Critical handle rules:**
1. `@handle = value` sets the handle to point at the object
2. `handle = value` copies the VALUE (if value type) -- this is a common bug source
3. Multiple handles can point to the same object
4. When the last handle is released, the object is destroyed (reference counting)
5. NOT all types support handles -- value types (like `AIFloat3`, `SResource`) do NOT have handles

```angelscript
// CORRECT: set handle to point at a new object
CCircuitUnit@ unit = null;
@unit = ai.GetTeamUnit(someId);

// WRONG for reference types: this copies the value, not the handle
// unit = ai.GetTeamUnit(someId);  // Compile error or unexpected behavior
```

From Barb3 builder.as -- real handle usage:
```angelscript
CCircuitUnit@ primaryT1BotConstructor = null;
CCircuitUnit@ secondaryT1BotConstructor = null;

// Setting a handle in assignment
@Builder::primaryT1BotConstructor = @unit;

// Clearing a handle
@Builder::primaryT1BotConstructor = null;
```

References:
- [AngelScript Object Handles](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_script_handle.html)
- [Objects and Handles](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_datatypes_obj.html)

### Null Checks: `!is null` (NOT `!= null`)

This is a **gotcha that will bite you**. AngelScript uses identity operators for null checks, not equality operators:

```angelscript
// CORRECT: use 'is' and '!is' for null checks
if (def !is null) {
    AiLog("Found: " + def.GetName());
}

if (unit is null) {
    return;  // unit was destroyed or never assigned
}

// WRONG: do NOT use == or != for null checks
// if (def != null) { ... }   // This won't compile or won't work as expected
```

The `is` and `!is` operators compare **identity** (same memory address), not equality. They are the ONLY way to check for null handles.

From Barb3 `setup.as`:
```angelscript
CCircuitDef@ def = (fac != "") ? ai.GetCircuitDef(fac) : null;
if (def !is null && def.IsAvailable(ai.frame)) {
    Global::AISettings::StartFactory = fac;
    @result = def;
}
```

### Arrays

Arrays are template reference types:

```angelscript
// Declaration and initialization
array<string> names = {"armcom", "corcom", "legcom"};
array<float> weights = {0.5f, 0.3f, 0.2f};
array<int> empty;       // empty array

// Access
string first = names[0];
uint count = names.length();

// Modification
names.insertLast("newunit");
names.insertAt(0, "default");
names.removeAt(2);
names.sortAsc();

// Iteration
for (uint i = 0; i < names.length(); ++i) {
    AiLog(names[i]);
}

// Array handle (passing arrays around efficiently)
array<string>@ keys = myDict.getKeys();
```

From Barb3 `common.as` -- real array usage:
```angelscript
array<string> armors = {
    "commanders", "scavboss", "indestructable", "crawlingbombs",
    "walls", "standard", "space", "mines", "nanos", "vtol",
    "shields", "lboats", "hvyboats", "subs", "raptor"
};
armors.sortAsc();
armors.insertAt(0, "default");
```

### Dictionaries

Dictionaries are string-keyed hash maps that can store any value type:

```angelscript
// Declaration
dictionary myDict;

// Setting values (stores variant types)
myDict.set("count", 42);
myDict.set("name", "armcom");
myDict.set("active", true);

// Getting values (must provide typed output variable)
int count;
myDict.get("count", count);    // count = 42

string name;
myDict.get("name", name);      // name = "armcom"

// Checking existence
bool exists = myDict.exists("count");

// Deleting
myDict.delete("count");

// Getting all keys
array<string>@ keys = myDict.getKeys();

// Storing handle references in dictionaries
dictionary unitRegistry;
unitRegistry.set("" + unit.id, @unit);    // key must be string
```

From Barb3 `global.as` -- real dictionary usage:
```angelscript
// MexUpgrades tracking uses dictionary with string keys
namespace MexUpgrades {
    dictionary spots;  // key: "gx,gz" grid cell; value: AIFloat3

    string Key(const AIFloat3 &in p) {
        const float step = 2.0f * SQUARE_SIZE;
        const int gx = int(floor((p.x + 0.5f * step) / step));
        const int gz = int(floor((p.z + 0.5f * step) / step));
        return gx + "," + gz;
    }

    void Add(IUnitTask@ t) {
        if (t is null) return;
        AIFloat3 p = t.GetBuildPos();
        spots.set(Key(p), p);
    }
}
```

### Namespaces

Namespaces work like C++/C#:

```angelscript
namespace Task {
    enum Priority { LOW = 0, NORMAL = 1, HIGH = 2, NOW = 99 }
    enum BuildType { FACTORY = 0, NANO, STORE, PYLON, ENERGY, ... }
}

// Access with ::
Task::Priority prio = Task::Priority::HIGH;
Task::BuildType bt = Task::BuildType::MEX;

// Nested namespaces
namespace Global {
    namespace Economy {
        float MetalIncome = 0.0f;
        float GetMetalIncome() { return MetalIncome; }
    }
    namespace Map {
        bool HasStart = false;
        AIFloat3 StartPos(0,0,0);
    }
}

// Deep access
float mi = Global::Economy::GetMetalIncome();
```

Barb3 uses namespaces extensively for organization: `Builder::`, `Economy::`, `Factory::`, `Military::`, `TaskB::`, `TaskS::`, `TaskF::`, `Global::`, `Side::`, `Unit::Role::`, `Unit::Attr::`, etc.

### Classes and Structs

AngelScript classes are reference types by default:

```angelscript
class MapConfig {
    string name;
    bool isLandLocked;

    // Constructor
    MapConfig() {
        name = "";
        isLandLocked = false;
    }

    // Methods
    string GetName() { return name; }
}

// Structs are value types when registered by C++ (like AIFloat3, SResource)
// You don't define new value types in script -- they come from C++
```

### Enums

```angelscript
namespace Task {
    enum Priority {
        LOW = 0, NORMAL = 1, HIGH = 2, NOW = 99
    }
    enum BuildType {
        FACTORY = 0, NANO, STORE, PYLON, ENERGY, GEO, GEOUP,
        DEFENCE, BUNKER, BIG_GUN, RADAR, SONAR, CONVERT,
        MEX, MEXUP, REPAIR, RECLAIM, RESURRECT, RECRUIT, TERRAFORM,
        _SIZE_,                                    // sentinel for selectable count
        PATROL, GUARD, COMBAT, WAIT               // non-reassignable actions
    }
}

// Usage with explicit cast (required when going int -> enum)
Task::BuildType bt = Task::BuildType(t.GetBuildType());
```

### Parameter Modifiers: `const`, `&in`, `&out`

```angelscript
// &in = input reference (read-only, caller's value is NOT modified)
void LogPos(const AIFloat3 &in pos) {
    AiLog("x=" + pos.x + " z=" + pos.z);
}

// &out = output reference (function writes to caller's variable)
void ExtractTaskBuildMeta(IUnitTask@ t, string &out defName, int &out buildTypeVal) {
    defName = "";
    buildTypeVal = -1;
    if (t is null) return;
    CCircuitDef@ d = t.GetBuildDef();
    if (d !is null) defName = d.GetName();
}

// Usage of &out
string name; int typeVal;
ExtractTaskBuildMeta(task, name, typeVal);  // name and typeVal are now filled

// @+ = auto-handle (C++ side manages reference counting automatically)
IUnitTask@+ DefaultMakeTask(CCircuitUnit@ unit);
```

### `#include` System

AngelScript uses file-based includes (like C/C++):

```angelscript
#include "../define.as"
#include "../global.as"
#include "../helpers/generic_helpers.as"
#include "../types/strategy.as"
```

- Paths are relative to the including file
- No header guards needed (the engine handles duplicate includes)
- Circular includes can cause issues -- Barb3 uses a tree structure to avoid this

### Control Flow

Standard C-family syntax:

```angelscript
// if/else
if (metalIncome > 50.0f) {
    BuildFactory();
} else if (metalIncome > 20.0f) {
    BuildSolar();
} else {
    WaitForResources();
}

// Ternary
string label = (def !is null) ? def.GetName() : "<null>";

// for loop
for (uint i = 0; i < names.length(); ++i) {
    AiLog(names[i]);
}

// while
while (count > 0) {
    ProcessNext();
    count--;
}

// switch/case
switch (bt) {
    case Task::BuildType::FACTORY: return "FACTORY";
    case Task::BuildType::MEX:     return "MEX";
    case Task::BuildType::ENERGY:  return "ENERGY";
    default: return "UNKNOWN";
}
```

### Key Differences from Other Languages

| Feature | AngelScript | Lua | C++ | C# |
|---------|-------------|-----|-----|----|
| Typing | Static | Dynamic | Static | Static |
| Compilation | At load time | Interpreted/JIT | Compiled | JIT |
| Memory | Ref counting | GC | Manual | GC |
| Null check | `!is null` | `~= nil` | `!= nullptr` | `!= null` |
| Handle | `@` | N/A | `shared_ptr` | reference |
| Strings | `string` (ref type) | `string` (value) | `std::string` | `string` |
| Arrays | `array<T>` | `table` | `std::vector` | `List<T>` |

---

## 2. CircuitAI Architecture

### Overview

[CircuitAI](https://github.com/rlcevg/CircuitAI) is a native C++ AI for the Spring/Recoil RTS engine, created by rlcevg. Barb3 (the BAR barbarian AI) is a fork/variant that adds AngelScript scripting on top of CircuitAI's C++ core.

```
+-----------------------------------------------------------+
|                    Spring/Recoil Engine                     |
|  (game loop, physics, rendering, unit commands)            |
+----------------------------+------------------------------+
                             |
                    Skirmish AI Interface
                             |
+----------------------------v------------------------------+
|                   CircuitAI C++ Core                       |
|  (SkirmishAI.dll)                                         |
|                                                            |
|  CCircuitAI  --- main AI brain, holds all managers         |
|    |                                                       |
|    +-- CBuilderManager   (building placement, tasks)       |
|    +-- CEconomyManager   (resource tracking, stalls)       |
|    +-- CFactoryManager   (factory production queues)       |
|    +-- CMilitaryManager  (combat unit assignment)          |
|    +-- CSetupManager     (mod options, init)               |
|                                                            |
+----------------------------+------------------------------+
                             |
                    AngelScript Engine
                             |
+----------------------------v------------------------------+
|               AngelScript Scripting Layer                   |
|  (loaded at runtime from script/ directory)                |
|                                                            |
|  init.as    -- AiInit(): armor, categories, profiles       |
|  main.as    -- AiMain(): map setup, strategy dice          |
|                AiUpdate(): periodic tick (every 30 frames) |
|  manager/   -- MakeTask() entry points per manager         |
|  helpers/   -- Pure logic functions                        |
|  roles/     -- Role-specific behavior (front, tech, air)   |
|  types/     -- Enums, configs, data structures             |
|  maps/      -- Per-map configuration overrides             |
+-----------------------------------------------------------+
```

### Manager Hierarchy

The C++ core exposes **global manager objects** to AngelScript:

| Global Object | C++ Class | Purpose |
|---------------|-----------|---------|
| `ai` | `CCircuitAI` | Main AI object -- frame counter, unit lookups, map info |
| `aiBuilderMgr` | `CBuilderManager` | Building placement, task creation, worker management |
| `aiEconomyMgr` | `CEconomyManager` | Resource tracking, stall detection, income rates |
| `aiFactoryMgr` | `CFactoryManager` | Factory production queues, unit recruitment |
| `aiMilitaryMgr` | `CMilitaryManager` | Combat unit task assignment |
| `aiSetupMgr` | `CSetupManager` | Mod options, initialization data |
| `aiRoleMasker` | `CMaskHandler` | Role type mask lookups |
| `aiAttrMasker` | `CMaskHandler` | Attribute type mask lookups |
| `aiSideMasker` | `CMaskHandler` | Faction side mask lookups |

### Script Entry Points

The C++ core calls into AngelScript at specific moments:

| Entry Point | When Called | Namespace |
|-------------|------------|-----------|
| `AiInit()` | AI startup | `Init::` |
| `AiMain()` | After init, once | `Main::` |
| `AiUpdate()` | Every 30 frames (~1 sec) | `Main::` |
| `Builder::MakeTask(unit)` | Builder unit is idle | `Builder::` |
| `Factory::MakeTask(unit)` | Factory unit is idle | `Factory::` |
| `Military::MakeTask(unit)` | Military unit is idle | `Military::` |
| `Economy::AiUpdateEconomy()` | Economy tick | `Economy::` |
| `Economy::OpenStrategy(facDef, pos)` | Opening strategy decision | `Economy::` |
| `Factory::AiGetFactoryToBuild(pos, isStart, isReset)` | Factory selection | `Factory::` |
| `Factory::AiIsSwitchTime(frame)` | Factory switch check | `Factory::` |
| `Main::AiLuaMessage(data)` | Lua widget sends message | `Main::` |

### Configuration Layer

Barb3 uses JSON profile files loaded by C++ that configure default behavior:

```
Prod/Skirmish/Barb3/stable/
  profile/
    ArmadaBehaviour.json    -- unit role/attribute assignments
    CortexBehaviour.json
    ArmadaBuildChain.json   -- build order weights
    block_map.json          -- placement restrictions
    commander.json          -- commander behavior
    ArmadaFactory.json      -- factory production tables
    ...
```

The AngelScript layer can **override** the defaults set by these JSON profiles.

---

## 3. Key API Classes

### CCircuitAI (`ai`) -- Main AI Object

The central access point. Available as the global `ai` variable in all scripts.

**Properties:**
```angelscript
const int ai.frame;           // Current simulation frame (30 fps at speed 1.0)
const int ai.skirmishAIId;    // Unique AI instance ID
const int ai.teamId;          // AI's team number
const int ai.allyTeamId;      // Allied team ID
```

**Methods:**
```angelscript
CCircuitDef@ ai.GetCircuitDef(const string &in name);  // Get unit def by name
CCircuitDef@ ai.GetCircuitDef(Id defId);                // Get unit def by ID
int ai.GetDefCount() const;                              // Total unit definitions
string ai.GetMapName() const;                            // Current map name
CCircuitUnit@ ai.GetTeamUnit(Id id);                     // Get live unit by ID
bool ai.IsLoadSave() const;                              // Load/save state
Type ai.GetBindedRole(Type type) const;                  // Get bound role
int ai.GetLeadTeamId() const;                            // Leader team ID
```

**Barb3 example:**
```angelscript
// From setup.as -- checking factory availability
CCircuitDef@ def = ai.GetCircuitDef("armlab");
if (def !is null && def.IsAvailable(ai.frame)) {
    AiLog("Bot lab available at frame " + ai.frame);
}

// From generic_helpers.as -- structured logging
AiLog(":::AI LOG:S:" + ai.skirmishAIId + ":T:" + ai.teamId +
      ":F:" + ai.frame + ":L:" + ":" + message);
```

### CCircuitDef -- Unit Definition

Represents a unit TYPE (not an instance). Think of it as the blueprint.

**Properties:**
```angelscript
const Id def.id;        // Unique definition ID
const float def.health; // Max health points
const float def.speed;  // Movement speed
const float def.costM;  // Metal cost to build
const float def.costE;  // Energy cost to build
```

**Methods:**
```angelscript
const string def.GetName() const;       // Internal name (e.g., "armlab", "armmex")
bool def.IsAbleToFly() const;           // Can this unit fly?
bool def.IsAvailable(int frame) const;  // Available at this frame?
bool def.IsMobile() const;              // Is this a mobile unit?
void def.AddAttribute(Type attr);       // Add attribute flag
void def.DelAttribute(Type attr);       // Remove attribute flag
```

**Barb3 example:**
```angelscript
// From main.as -- marking T2 factories
array<string> names = {Factory::armalab, Factory::coralab, Factory::armavp, Factory::coravp};
for (uint i = 0; i < names.length(); ++i)
    Factory::userData[ai.GetCircuitDef(names[i]).id].attr |= Factory::Attr::T2;
```

### CCircuitUnit -- Live Unit Instance

Represents an actual unit on the battlefield. **CRITICAL WARNING from Barb3 source:**

> CCircuitUnit is registered as `asOBJ_NOCOUNT`. Script handles do NOT keep the native alive; any method/property may deref freed memory. Always pass IDs around and reacquire with `ai.GetTeamUnit(id)` before native calls.

**Properties:**
```angelscript
const Id unit.id;                  // Runtime unit ID
CCircuitDef@ unit.circuitDef;     // Handle to unit's definition
```

**Methods:**
```angelscript
AIFloat3 unit.GetPos(int frame);  // Current position at given frame
bool unit.IsAttrAny(uint mask);   // Check if unit has any of the given attributes
```

**Barb3 safe pattern (from builder.as):**
```angelscript
// ALWAYS reacquire before calling methods
IUnitTask@ MakeDefaultTaskWithLog(Id unitId, const string &in roleLabel)
{
    CCircuitUnit@ v = ai.GetTeamUnit(unitId);   // Reacquire!
    if (v is null) {
        return null;                              // Unit died
    }
    IUnitTask@ t = aiBuilderMgr.DefaultMakeTask(v);

    string unitDefName = (v.circuitDef !is null) ? v.circuitDef.GetName() : "<null>";
    const AIFloat3 p = v.GetPos(ai.frame);
    GenericHelpers::LogUtil("[Builder] task=" + t.GetType() +
        " unit=" + unitDefName + " pos=(" + p.x + "," + p.z + ")", 3);
    return t;
}
```

### AIFloat3 -- 3D Position Vector

Value type (no handles). Used for all positions and directions.

**Properties:**
```angelscript
float pos.x;  // East-West (map horizontal)
float pos.y;  // Height (usually 0 for ground)
float pos.z;  // North-South (map vertical)
```

**Constructors:**
```angelscript
AIFloat3 origin;                          // (0, 0, 0)
AIFloat3 pos(100.0f, 0.0f, 200.0f);     // Specific coordinates
AIFloat3 copy(otherPos);                  // Copy constructor
```

**Barb3 example:**
```angelscript
// From global.as
AIFloat3 StartPos(0,0,0);

// Distance check helper
float SqDist(const AIFloat3 &in a, const AIFloat3 &in b) {
    float dx = a.x - b.x;
    float dz = a.z - b.z;
    return dx*dx + dz*dz;
}
```

### SResource -- Metal/Energy Cost

Value type holding resource amounts.

```angelscript
SResource cost(50.0f, 20.0f);   // metal=50, energy=20
float m = cost.metal;
float e = cost.energy;
```

### SBuildTask -- Building Task (CRITICAL for our quest)

This is **THE** struct we need to understand for overriding AI building placement.

**Properties:**
```angelscript
uint8 type;            // Task::BuildType enum value
uint8 priority;        // Task::Priority enum value
CCircuitDef@ buildDef; // WHAT to build (unit definition handle)
AIFloat3 position;     // WHERE to build (map coordinates)
SResource cost;        // Resource cost (metal, energy)
CCircuitDef@ reprDef;  // Representative def (for factory task pairing)
CCircuitUnit@ target;  // Target unit (for repair/reclaim tasks)
int pointId;           // Power grid point ID (-1 if none)
int spotId;            // Mex/geo spot ID (for resource spot tasks)
float shake;           // Position randomization radius (elmos)
float radius;          // Task radius (for reclaim area tasks)
bool isPlop;           // Commander instant-build ("plop") task?
bool isMetal;          // Is this a metal-related task?
bool isActive;         // Should this go to the general queue?
int timeout;           // Task timeout in frames
```

**Barb3 task construction helpers (from `task.as`):**

```angelscript
namespace TaskB {
    // General-purpose build task
    SBuildTask Common(Task::BuildType type, Task::Priority priority,
            CCircuitDef@ buildDef, const AIFloat3 &in position,
            float shake = SQUARE_SIZE * 32,   // default: 256 elmos randomization
            bool isActive = true,
            int timeout = ASSIGN_TIMEOUT)      // default: 5 minutes
    {
        SBuildTask ti;
        ti.type = type;
        ti.priority = priority;
        @ti.buildDef = buildDef;
        ti.position = position;
        ti.shake = shake;
        ti.isActive = isActive;
        ti.timeout = timeout;
        ti.cost = SResource(0.f, 0.f);
        @ti.reprDef = null;
        ti.pointId = -1;
        ti.isPlop = false;
        return ti;
    }

    // Mex/geo spot task (includes spotId)
    SBuildTask Spot(Task::BuildType type, Task::Priority priority,
            CCircuitDef@ buildDef, const AIFloat3 &in position, int spotId,
            bool isActive = true, int timeout = ASSIGN_TIMEOUT)
    { ... }

    // Factory task (includes reprDef for factory-unit pairing, plop flag)
    SBuildTask Factory(Task::Priority priority, CCircuitDef@ buildDef,
            const AIFloat3 &in position, CCircuitDef@ reprDef,
            float shake = SQUARE_SIZE * 32, bool isPlop = false,
            bool isActive = true, int timeout = ASSIGN_TIMEOUT)
    { ... }
}
```

### SServBTask -- Builder Service Task

For non-construction builder actions (patrol, guard, combat, wait).

```angelscript
uint8 type;              // Task::BuildType (PATROL, GUARD, COMBAT, WAIT)
uint8 priority;          // Task::Priority
AIFloat3 position;       // Target position
CCircuitUnit@ target;    // Target unit (for guard tasks)
float powerMod;          // Power modifier (for combat tasks)
bool isInterrupt;        // Can this task be interrupted?
int timeout;             // Timeout in frames
```

**Barb3 service task helpers:**
```angelscript
namespace TaskB {
    SServBTask Guard(Task::Priority priority,
            CCircuitUnit@ target, bool isInterrupt, int timeout = ASSIGN_TIMEOUT)
    { ... }

    SServBTask Patrol(Task::Priority priority,
            const AIFloat3 &in position, int timeout)
    { ... }

    SServBTask Combat(float powerMod)
    { ... }
}
```

### CBuilderManager (`aiBuilderMgr`)

**THE interface for controlling what gets built.** This is the most critical manager for our quest.

**Methods:**
```angelscript
// Let C++ decide what to build (uses block_map.json, profile configs)
IUnitTask@+ aiBuilderMgr.DefaultMakeTask(CCircuitUnit@ unit);

// Enqueue a custom build task -- THIS IS HOW WE OVERRIDE PLACEMENT
IUnitTask@+ aiBuilderMgr.Enqueue(const SBuildTask &in task);

// Enqueue a service task (guard, patrol, combat)
IUnitTask@+ aiBuilderMgr.Enqueue(const SServBTask &in task);

// Enqueue a retreat
IUnitTask@+ aiBuilderMgr.EnqueueRetreat();

// Count of active workers
uint aiBuilderMgr.GetWorkerCount() const;
```

**Usage pattern from Barb3:**
```angelscript
// Default behavior (C++ decides based on JSON profiles)
IUnitTask@ task = aiBuilderMgr.DefaultMakeTask(unit);

// Custom build task (script overrides what to build)
SBuildTask buildTask = TaskB::Common(
    Task::BuildType::ENERGY,
    Task::Priority::HIGH,
    ai.GetCircuitDef("armsolar"),
    unit.GetPos(ai.frame),
    SQUARE_SIZE * 32    // shake radius
);
aiBuilderMgr.Enqueue(buildTask);

// Guard another unit
SServBTask guardTask = TaskB::Guard(
    Task::Priority::NORMAL,
    targetUnit,
    true,               // interruptible
    ASSIGN_TIMEOUT
);
aiBuilderMgr.Enqueue(guardTask);
```

### CEconomyManager (`aiEconomyMgr`)

Tracks the AI's economy state. Read-only information used to make build decisions.

**Properties:**
```angelscript
const SResourceInfo aiEconomyMgr.metal;     // Metal resource state
const SResourceInfo aiEconomyMgr.energy;    // Energy resource state
bool aiEconomyMgr.isMetalEmpty;             // Metal nearly depleted?
bool aiEconomyMgr.isMetalFull;              // Metal storage nearly full?
bool aiEconomyMgr.isEnergyStalling;         // Energy demand > production?
bool aiEconomyMgr.isEnergyEmpty;            // Energy nearly depleted?
bool aiEconomyMgr.isEnergyFull;             // Energy storage nearly full?
float aiEconomyMgr.reclConvertEff;          // Reclaim-to-metal efficiency
float aiEconomyMgr.reclEnergyEff;           // Reclaim-to-energy efficiency
```

**SResourceInfo (metal or energy details):**
```angelscript
const float info.current;   // Current stored amount
const float info.storage;   // Maximum storage capacity
const float info.pull;      // Current consumption rate (per frame)
const float info.income;    // Current production rate (per frame)
```

**Methods:**
```angelscript
float aiEconomyMgr.GetMetalMake(const CCircuitDef@);   // Metal production of a unit type
float aiEconomyMgr.GetEnergyMake(const CCircuitDef@);  // Energy production of a unit type
```

**Barb3 economy pattern:**
```angelscript
// From economy.as -- updating global economy state
void AiUpdateEconomy() {
    Global::Economy::MetalIncome  = aiEconomyMgr.metal.income;
    Global::Economy::EnergyIncome = aiEconomyMgr.energy.income;
    Global::Economy::MetalCurrent  = aiEconomyMgr.metal.current;
    Global::Economy::EnergyCurrent = aiEconomyMgr.energy.current;
    Global::Economy::MetalStorage  = aiEconomyMgr.metal.storage;
    Global::Economy::EnergyStorage = aiEconomyMgr.energy.storage;
}
```

### CFactoryManager (`aiFactoryMgr`)

Controls factory unit production.

**Methods:**
```angelscript
IUnitTask@+ aiFactoryMgr.DefaultMakeTask(CCircuitUnit@ unit);
IUnitTask@+ aiFactoryMgr.Enqueue(const SRecruitTask &in task);
IUnitTask@+ aiFactoryMgr.Enqueue(const SServSTask &in task);
CCircuitDef@ aiFactoryMgr.GetRoleDef(const CCircuitDef@ factoryDef, Type role);
int aiFactoryMgr.GetFactoryCount();
CCircuitDef@ aiFactoryMgr.DefaultGetFactoryToBuild(const AIFloat3 &in pos, bool isStart, bool isReset);
```

**Properties:**
```angelscript
bool aiFactoryMgr.isAssistRequired;  // Does a factory need construction help?
```

**SRecruitTask (factory production task):**
```angelscript
uint8 type;            // Task::RecruitType (BUILDPOWER, FIREPOWER)
uint8 priority;        // Task::Priority
CCircuitDef@ buildDef; // What unit to produce
AIFloat3 position;     // Position context
float radius;          // Radius of influence
```

**Barb3 factory usage:**
```angelscript
// Recruit a unit from a factory
SRecruitTask task = TaskS::Recruit(
    Task::RecruitType::FIREPOWER,
    Task::Priority::HIGH,
    ai.GetCircuitDef("armwar"),       // Warrior bot
    factoryUnit.GetPos(ai.frame),
    500.0f
);
aiFactoryMgr.Enqueue(task);

// Get the role-appropriate unit for a factory
CCircuitDef@ scoutDef = aiFactoryMgr.GetRoleDef(factoryDef, Unit::Role::SCOUT.type);
```

### CMilitaryManager (`aiMilitaryMgr`)

Assigns tasks to combat units.

```angelscript
IUnitTask@+ aiMilitaryMgr.DefaultMakeTask(CCircuitUnit@ unit);
```

### IUnitTask -- Task Interface

The opaque handle returned when tasks are created. Used to inspect active tasks.

```angelscript
Type task.GetType() const;           // Task::Type (BUILDER, FACTORY, FIGHTER, etc.)
Type task.GetBuildType() const;      // Task::BuildType (MEX, ENERGY, FACTORY, etc.)
const AIFloat3& task.GetBuildPos() const;  // Where the build is happening
CCircuitDef@ task.GetBuildDef() const;     // What is being built
```

**Barb3 task inspection pattern:**
```angelscript
void ExtractTaskBuildMeta(IUnitTask@ t, string &out defName, int &out buildTypeVal)
{
    defName = "";
    buildTypeVal = -1;
    if (t is null) return;
    Task::Type ttype = Task::Type(t.GetType());
    if (ttype != Task::Type::BUILDER) return;
    int btVal = t.GetBuildType();
    buildTypeVal = btVal;
    CCircuitDef@ d = t.GetBuildDef();
    if (d !is null) defName = d.GetName();
}
```

### CMaskHandler (`aiRoleMasker`, `aiAttrMasker`, `aiSideMasker`)

Handles type mask lookups for the role/attribute/faction systems.

```angelscript
TypeMask aiRoleMasker.GetTypeMask(const string &in name);
TypeMask aiAttrMasker.GetTypeMask(const string &in name);
TypeMask aiSideMasker.GetTypeMask(const string &in name);
```

**Barb3 role definitions (from `unit.as`):**
```angelscript
namespace Unit {
    namespace Role {
        TypeMask BUILDER = aiRoleMasker.GetTypeMask("builder");
        TypeMask SCOUT   = aiRoleMasker.GetTypeMask("scout");
        TypeMask RAIDER  = aiRoleMasker.GetTypeMask("raider");
        TypeMask RIOT    = aiRoleMasker.GetTypeMask("riot");
        TypeMask ASSAULT = aiRoleMasker.GetTypeMask("assault");
        // ... many more

        // Custom roles added by Barb3
        TypeMask SPAM = AiAddRole("spam", ASSAULT.type);
        TypeMask ANTI_NUKE = AiAddRole("anti_nuke", STATIC.type);
    }
}
```

---

## 4. Task::BuildType Enum

The complete list of build task types, from `Prod/Skirmish/Barb3/stable/script/src/task.as`:

| Value | Name | Purpose |
|-------|------|---------|
| 0 | `FACTORY` | Build a factory (bot lab, vehicle plant, shipyard, etc.) |
| 1 | `NANO` | Build a nano caretaker (construction turret) |
| 2 | `STORE` | Build a resource storage structure |
| 3 | `PYLON` | Build a power grid pylon |
| 4 | `ENERGY` | Build an energy generator (solar, fusion, etc.) |
| 5 | `GEO` | Build a geothermal generator |
| 6 | `GEOUP` | Upgrade a geothermal generator |
| 7 | `DEFENCE` | Build a defense turret |
| 8 | `BUNKER` | Build a bunker/fortification |
| 9 | `BIG_GUN` | Build a superweapon (nuke silo, LRPC, etc.) |
| 10 | `RADAR` | Build a radar tower |
| 11 | `SONAR` | Build a sonar station |
| 12 | `CONVERT` | Build an energy converter (metal maker) |
| 13 | `MEX` | Build a metal extractor |
| 14 | `MEXUP` | Upgrade a metal extractor to T2 |
| 15 | `REPAIR` | Repair a damaged unit/structure |
| 16 | `RECLAIM` | Reclaim wreckage or features |
| 17 | `RESURRECT` | Resurrect a wreck |
| 18 | `RECRUIT` | Build units (factory context) |
| 19 | `TERRAFORM` | Terraform the terrain |
| -- | `_SIZE_` | Sentinel: count of selectable task types (20) |
| 20 | `PATROL` | Patrol action (cannot be reassigned) |
| 21 | `GUARD` | Guard action (cannot be reassigned) |
| 22 | `COMBAT` | Combat action (cannot be reassigned) |
| 23 | `WAIT` | Wait action (cannot be reassigned) |

**Note:** Types after `_SIZE_` are builder SERVICE actions, not construction tasks. They use `SServBTask` instead of `SBuildTask`.

---

## 5. Task::Priority Enum

From `Prod/Skirmish/Barb3/stable/script/src/task.as`:

| Value | Name | Meaning |
|-------|------|---------|
| 0 | `LOW` | Background task, will be preempted by higher priorities |
| 1 | `NORMAL` | Standard priority, default for most builds |
| 2 | `HIGH` | Elevated priority, built before normal tasks |
| 99 | `NOW` | Immediate -- drop everything and do this first |

**Usage pattern:**
```angelscript
// Regular mex
task.priority = Task::Priority::NORMAL;

// Urgent factory when none exist
task.priority = Task::Priority::NOW;

// Background solar
task.priority = Task::Priority::LOW;
```

---

## 6. How Build Tasks Work in Practice

### The Complete Flow

```
Step 1: C++ Engine detects an idle builder unit
        |
        v
Step 2: C++ calls AngelScript entry point
        Builder::MakeTask(CCircuitUnit@ unit)
        |
        v
Step 3: AngelScript role handler decides what to build
        (based on economy state, role, strategy, etc.)
        |
        +---> Option A: Let C++ decide (default)
        |     aiBuilderMgr.DefaultMakeTask(unit)
        |     C++ reads block_map.json, profile JSONs
        |     C++ finds valid position, creates task
        |
        +---> Option B: Script creates custom task
              Creates SBuildTask with type, priority, buildDef
              Calls aiBuilderMgr.Enqueue(task)
              C++ validates position, applies constraints
        |
        v
Step 4: C++ gives the builder a move+build order
        Builder physically moves to position and starts building
        |
        v
Step 5: Building completes (or fails/times out)
        Builder becomes idle again -> back to Step 1
```

### Concrete Example: Building a Solar Generator

```angelscript
// This happens inside a Builder::MakeTask handler
IUnitTask@ MakeTask(CCircuitUnit@ unit)
{
    // Check economy state
    float ei = Global::Economy::GetEnergyIncome();

    // Need more energy?
    if (EconomyHelpers::ShouldBuildT1Solar(ei,
            Global::RoleSettings::Tech::SolarEnergyIncomeMinimum))
    {
        // Get the solar panel definition for our faction
        CCircuitDef@ solarDef = ai.GetCircuitDef(
            UnitHelpers::GetT1SolarForSide(Global::AISettings::Side)
        );

        if (solarDef !is null) {
            // Create a build task
            SBuildTask task = TaskB::Common(
                Task::BuildType::ENERGY,       // type: energy structure
                Task::Priority::NORMAL,        // normal priority
                solarDef,                      // what to build
                unit.GetPos(ai.frame),         // near this unit
                SQUARE_SIZE * 32               // 256 elmo shake radius
            );
            return aiBuilderMgr.Enqueue(task);
        }
    }

    // Fall back to C++ default behavior
    return aiBuilderMgr.DefaultMakeTask(unit);
}
```

### How DefaultMakeTask Works

When you call `aiBuilderMgr.DefaultMakeTask(unit)`, the C++ core:

1. Reads the unit's current role and attributes
2. Consults `block_map.json` for placement constraints
3. Checks `*BuildChain.json` for build order priorities
4. Evaluates economy state for resource requirements
5. Finds a valid build position using pathfinding
6. Creates and returns an `IUnitTask@` handle

The script can then inspect the task or override it entirely.

### How Enqueue Works

When you call `aiBuilderMgr.Enqueue(task)`, the C++ core:

1. Takes the `SBuildTask` struct you created
2. Validates the `buildDef` is buildable by the builder
3. Applies `block_map.json` constraints to the position
4. Adjusts position by `shake` radius for randomization
5. Finds the nearest valid build location
6. Creates an internal task and assigns it to a worker
7. Returns an `IUnitTask@` handle for tracking

**Important:** Even when you specify a position in `SBuildTask`, C++ may adjust it based on terrain, blocking zones, and other constraints. The `shake` parameter controls how much randomization is applied.

---

## 7. How to Add New Behavior

### File Organization

Barb3 script files live in:
```
Prod/Skirmish/Barb3/stable/script/
  src/                          -- Shared source files
    common.as                   -- Faction registration, armor/category init
    define.as                   -- Constants (SECOND, MINUTE, SQUARE_SIZE)
    global.as                   -- Global state (economy, map, settings)
    task.as                     -- Task enums and SBuildTask/SServBTask helpers
    unit.as                     -- Role and attribute definitions
    maps.as                     -- Map config includes and registration
    setup.as                    -- Initialization, factory selection, map setup
    manager/
      builder.as                -- Builder MakeTask and worker management
      economy.as                -- Economy update and strategy
      factory.as                -- Factory MakeTask and production
      military.as               -- Military MakeTask
    helpers/
      generic_helpers.as        -- LogUtil, RecordStart
      builder_helpers.as        -- Builder-specific predicates
      economy_helpers.as        -- Economy decision functions (HUGE file)
      factory_helpers.as        -- Factory selection logic
      task_helpers.as           -- Task type name formatters
      unit_helpers.as           -- Unit definition lookups by side/tier
      unitdef_helpers.as        -- Unit count tracking
      map_helpers.as            -- Distance/position utilities
      guard_helpers.as          -- Constructor guard assignment
      limits_helpers.as         -- Unit cap calculations
      role_helpers.as           -- Role assignment logic
    roles/
      front.as                  -- FRONT role behavior
      front_tech.as             -- FRONT_TECH role behavior
      tech.as                   -- TECH role behavior
      air.as                    -- AIR role behavior
      sea.as                    -- SEA role behavior
      hover_sea.as              -- HOVER_SEA role behavior
    types/
      strategy.as               -- Strategy enum and bitmask utilities
      ai_role.as                -- AiRole enum
      role_config.as            -- RoleConfig class (function delegates)
      profile_controller.as     -- Profile/role switching system
      building_type.as          -- BuildingType enum
      start_spot.as             -- StartSpot struct
    maps/
      default_map_config.as     -- Default map configuration
      factory_mapping.as        -- Factory-to-map mappings
      [per-map].as              -- Map-specific configs (50+ maps)
  experimental_balanced/        -- Difficulty variant entry points
    init.as                     -- AiInit() for this variant
    main.as                     -- AiMain() for this variant
  experimental_FiftyBonus/      -- Another difficulty variant
    init.as
    main.as
  ...
```

### Adding a New Build Decision

To add new building behavior:

1. **Create or modify a helper** in `script/src/helpers/`:
```angelscript
// economy_helpers.as
bool ShouldBuildMyNewThing(float metalIncome, float threshold) {
    return metalIncome > threshold;
}
```

2. **Call it from the role handler** in `script/src/roles/`:
```angelscript
// roles/tech.as (inside the MakeTask flow)
if (EconomyHelpers::ShouldBuildMyNewThing(mi, 100.0f)) {
    CCircuitDef@ def = ai.GetCircuitDef("armturret");
    SBuildTask task = TaskB::Common(
        Task::BuildType::DEFENCE,
        Task::Priority::NORMAL,
        def,
        builderPos
    );
    return aiBuilderMgr.Enqueue(task);
}
```

3. **Add configurable thresholds** in `script/src/global.as`:
```angelscript
namespace Global {
    namespace RoleSettings {
        namespace Tech {
            float MyNewThreshold = 100.0f;
        }
    }
}
```

### Modifying Factory Production

To change what a factory produces:

```angelscript
// In the factory MakeTask handler
CCircuitDef@ unitDef = aiFactoryMgr.GetRoleDef(factory.circuitDef, Unit::Role::RAIDER.type);
if (unitDef !is null) {
    SRecruitTask task = TaskS::Recruit(
        Task::RecruitType::FIREPOWER,
        Task::Priority::HIGH,
        unitDef,
        factory.GetPos(ai.frame),
        500.0f
    );
    aiFactoryMgr.Enqueue(task);
}
```

### Changes Take Effect on AI Restart

- **No recompilation needed** -- scripts are compiled at AI load time
- Restart the AI in-game: `/skip` or restart the match
- The AngelScript engine compiles all `.as` files when the AI initializes
- Compile errors show in the infolog (Spring's log output)

---

## 8. Logging and Debugging

### Primary Logging Functions

**`AiLog(string)`** -- Global function, always available:
```angelscript
AiLog("This is a basic log message");
AiLog("Metal income: " + aiEconomyMgr.metal.income);
```

**`GenericHelpers::LogUtil(msg, level)`** -- Barb3's leveled logging:
```angelscript
// Only prints if LOG_LEVEL >= level
// LOG_LEVEL is defined in define.as (default: 1)
GenericHelpers::LogUtil("Important message", 1);   // Level 1: always shown
GenericHelpers::LogUtil("Debug detail", 3);         // Level 3: only if LOG_LEVEL >= 3
GenericHelpers::LogUtil("Trace spam", 5);           // Level 5: very verbose

// With role context
GenericHelpers::LogUtil("Factory built", AiRole::TECH, 2);
```

**Log format:**
```
:::AI LOG:S:{skirmishAIId}:T:{teamId}:F:{frame}:L::message
:::AI LOG:S:0:T:1:F:4500:L:::[TECH][Builder] DefaultMakeTask created: taskType=5
```

### Log Levels in Barb3

| Level | Purpose | When to Use |
|-------|---------|-------------|
| 1 | Critical / Milestones | Game start, factory selection, role assignment |
| 2 | Important decisions | Economy thresholds crossed, build decisions |
| 3 | Detailed state | Task metadata, economy checks, guard assignments |
| 4 | Verbose/Trace | Function entry/exit, predicate evaluations |
| 5 | Ultra-verbose | Per-frame tracking, dictionary operations |
| 6 | Spam | Inner loop iterations |

### Where Logs Appear

Logs go to the **Spring/Recoil infolog**:

- **Windows:** `%LOCALAPPDATA%\Spring\infolog.txt` (or the game's data directory)
- **In-game console:** Press `F9` (or configured key) to see recent log output
- **Widget overlay:** Some BAR widgets display AI log output in real-time

### Debugging Patterns from Barb3

**Log task decisions:**
```angelscript
// From builder.as -- log every task assignment with full context
GenericHelpers::LogUtil(
    "[" + roleLabel + "][Builder] DefaultMakeTask created: taskType=" + taskTypeStr +
    " unitDef=" + unitDefName + " pos=(" + p.x + "," + p.z + ")", 3);
```

**Log economy state before decisions:**
```angelscript
GenericHelpers::LogUtil(
    "[Econ] ShouldBuildT2BotLab: mi=" + mi + "/" + requiredMetalIncome +
    " ei=" + ei + "/" + requiredEnergyIncome +
    " count=" + t2BotLabCount + "/max=" + maxAllowed +
    " => result=" + ((econOk && countOk) ? "true" : "false"), 3);
```

**Conditional debugging (change LOG_LEVEL to see more):**
```angelscript
// In define.as, change this to see more logs:
const uint LOG_LEVEL = 1;    // Production: only critical
const uint LOG_LEVEL = 3;    // Development: detailed decisions
const uint LOG_LEVEL = 5;    // Debug: everything
```

### AiPause -- Freeze for Inspection

```angelscript
// Pause the game with a reason string
AiPause(true, "Debugging: unexpected task type");

// Resume
AiPause(false, "");
```

### AiRandom and AiDice -- Randomization

```angelscript
// Random integer in range [min, max]
int roll = AiRandom(1, 100);

// Weighted random choice (returns index)
array<float> weights = {0.5f, 0.3f, 0.2f};
int choice = AiDice(weights);  // 0=50%, 1=30%, 2=20%
```

**Barb3 strategy dice example (from main.as):**
```angelscript
bool DecideEnabled(float probability) {
    float p = AiMax(0.0f, AiMin(probability, 1.0f));
    array<float>@ w = array<float>(2);
    w[0] = 1.0f - p;   // chance of OFF
    w[1] = p;           // chance of ON
    int idx = AiDice(w);
    return (idx == 1);
}

// 85% chance of enabling T2 rush strategy
if (DecideEnabled(0.85f)) {
    Global::RoleSettings::Tech::EnableStrategy(Strategy::T2_RUSH);
}
```

---

## Quick Reference Card

### Most-Used Patterns

```angelscript
// Get a unit definition
CCircuitDef@ def = ai.GetCircuitDef("armlab");

// Safe unit access (ALWAYS reacquire by ID)
CCircuitUnit@ u = ai.GetTeamUnit(unitId);
if (u is null) return null;

// Create and enqueue a build task
SBuildTask task = TaskB::Common(
    Task::BuildType::ENERGY,
    Task::Priority::NORMAL,
    def,
    u.GetPos(ai.frame)
);
IUnitTask@ result = aiBuilderMgr.Enqueue(task);

// Fall back to C++ default
return aiBuilderMgr.DefaultMakeTask(u);

// Check economy
float mi = Global::Economy::GetMetalIncome();
bool stalling = aiEconomyMgr.isEnergyStalling;

// Log something
GenericHelpers::LogUtil("[MyMod] Did a thing: x=" + x, 2);
```

### Key File Paths (Barb3)

| File | Path | Purpose |
|------|------|---------|
| Constants | `script/src/define.as` | SECOND, MINUTE, LOG_LEVEL |
| Global state | `script/src/global.as` | Economy, Map, Settings, RoleSettings |
| Task enums | `script/src/task.as` | BuildType, Priority, helper constructors |
| Unit roles | `script/src/unit.as` | Role masks, attribute masks |
| Builder mgr | `script/src/manager/builder.as` | MakeTask, worker tracking |
| Economy mgr | `script/src/manager/economy.as` | AiUpdateEconomy |
| Factory mgr | `script/src/manager/factory.as` | Factory MakeTask |
| Economy helpers | `script/src/helpers/economy_helpers.as` | All ShouldBuild* predicates |
| Generic helpers | `script/src/helpers/generic_helpers.as` | LogUtil |
| API reference | `angelscript-references.md` | Full C++ -> AS binding docs |

All paths relative to: `Prod/Skirmish/Barb3/stable/`

---

## Sources

- [AngelScript Official Documentation](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_script.html)
- [AngelScript Object Handles](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_script_handle.html)
- [AngelScript Objects and Handles](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_datatypes_obj.html)
- [AngelScript Arrays](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_datatypes_arrays.html)
- [AngelScript Dictionary](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_datatypes_dictionary.html)
- [AngelScript Datatypes Comparison](https://www.angelcode.com/angelscript/sdk/docs/manual/doc_as_vs_cpp_types.html)
- [CircuitAI GitHub Repository](https://github.com/rlcevg/CircuitAI)
- [CircuitAI Barbarian Branch](https://github.com/rlcevg/CircuitAI/tree/barbarian)
- [AngelScript Overview (Openplanet)](https://openplanet.dev/docs/tutorials/angelscript-overview)
- [AngelScript Fundamentals (Frictional Wiki)](https://wiki.frictionalgames.com/page/HPL3/Scripting/AngelScript_Fundamentals)
- [AngelScript Wikipedia](https://en.wikipedia.org/wiki/AngelScript)
