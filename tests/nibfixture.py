"""Write test nibs: keyed archives of an NSIBObjectData, the form Cocotron's NSNib reads."""
import plistlib

RESPONDER = ["NSResponder", "NSObject"]


class Archive:
    def __init__(self):
        self.objects = ["$null"]
        self.classes = {}

    def add(self, value):
        self.objects.append(value)
        return plistlib.UID(len(self.objects) - 1)

    def cls(self, name, supers):
        if name not in self.classes:
            self.classes[name] = self.add({"$classname": name, "$classes": [name] + supers})
        return self.classes[name]

    def obj(self, name, supers, **fields):
        uid = self.add(None)
        self.objects[uid.data] = dict(fields, **{"$class": self.cls(name, supers)})
        return uid

    def array(self, items):
        return self.obj("NSArray", ["NSObject"], **{"NS.objects": list(items)})

    def view(self, width, height):
        return self.obj("NSView", RESPONDER, NSFrame=self.add("{{0, 0}, {%d, %d}}" % (width, height)))

    def outlet(self, source, destination, label):
        return self.obj("NSNibOutletConnector", ["NSNibConnector", "NSObject"],
                        NSSource=source, NSDestination=destination, NSLabel=self.add(label))


def write_nib(path, build):
    """build(archive, owner) returns (top-level objects, connections); owner is the File's Owner."""
    a = Archive()
    owner = a.obj("NSCustomObject", ["NSObject"], NSClassName=a.add("NSObject"))
    top, connections = build(a, owner)
    data = a.obj("NSIBObjectData", ["NSObject"],
                 NSRoot=owner,
                 NSObjectsKeys=a.array(top), NSObjectsValues=a.array([owner] * len(top)),
                 NSNamesKeys=a.array([owner]), NSNamesValues=a.array([a.add("File's Owner")]),
                 NSConnections=a.array(connections),
                 NSVisibleWindows=a.obj("NSSet", ["NSObject"], **{"NS.objects": []}))
    with open(path, "wb") as f:
        plistlib.dump({"$archiver": "NSKeyedArchiver", "$version": 100000,
                       "$top": {"IB.objectdata": data}, "$objects": a.objects},
                      f, fmt=plistlib.FMT_BINARY)


def _varint(out, value):
    """NIBArchive varint: 7 bits per byte, least significant first, high bit set on the LAST byte."""
    while True:
        byte = value & 0x7f
        value >>= 7
        if not value:
            out.append(byte | 0x80)
            return
        out.append(byte)


def write_nibarchive(path, archive, top):
    """Write `archive` (an Archive whose `top` UID is the root object) in the NIBArchive layout.

    The layout is the one NSNibArchive.m parses (see its header comment): object 0 is a root whose
    single value, IB.objectdata, references the NSIBObjectData; strings become NSString objects
    with an NS.bytes data value, and collections store their elements as repeated
    UINibEncoderEmptyKey values.
    """
    import struct
    keys, classes, values, objects = [], [], [], []
    index = {}

    def intern(table, name):
        if name not in table:
            table.append(name)
        return table.index(name)

    # plist index -> NIB object index; strings become NSString objects, class descriptions vanish.
    order = [i for i, o in enumerate(archive.objects) if i and (isinstance(o, str) or (isinstance(o, dict) and "$class" in o))]
    for n, i in enumerate(order):
        index[i] = n + 1

    def value(key, item):
        k = intern(keys, key)
        if isinstance(item, plistlib.UID):
            if item.data == 0:
                return (k, 9, b"")
            return (k, 10, struct.pack("<I", index[item.data]))
        if isinstance(item, bool):
            return (k, 4 if item else 5, b"")
        if isinstance(item, int):
            if -2**31 <= item < 2**31:
                return (k, 2, struct.pack("<i", item))
            return (k, 3, struct.pack("<q", item))
        if isinstance(item, float):
            return (k, 7, struct.pack("<d", item))
        if isinstance(item, bytes):
            body = bytearray()
            _varint(body, len(item))
            return (k, 8, bytes(body) + item)
        raise TypeError("unsupported NIBArchive value %r for key %s" % (item, key))

    def add_object(class_name, members):
        first = len(values)
        values.extend(members)
        objects.append((intern(classes, class_name), first, len(members)))

    add_object("NSObject", [value("IB.objectdata", top)])
    for i in order:
        o = archive.objects[i]
        if isinstance(o, str):
            add_object("NSString", [value("NS.bytes", o.encode())])
            continue
        class_name = archive.objects[o["$class"].data]["$classname"]
        members = []
        for key, item in o.items():
            if key == "$class":
                continue
            if key == "NS.objects":
                members += [value("UINibEncoderEmptyKey", element) for element in item]
            else:
                members.append(value(key, item))
        add_object(class_name, members)

    obj_bytes, key_bytes, value_bytes, class_bytes = bytearray(), bytearray(), bytearray(), bytearray()
    for c, first, count in objects:
        for v in (c, first, count):
            _varint(obj_bytes, v)
    for name in keys:
        raw = name.encode()
        _varint(key_bytes, len(raw))
        key_bytes += raw
    for k, kind, payload in values:
        _varint(value_bytes, k)
        value_bytes.append(kind)
        value_bytes += payload
    for name in classes:
        raw = name.encode() + b"\0"
        _varint(class_bytes, len(raw))
        _varint(class_bytes, 0)
        class_bytes += raw
    offset = 50
    header = b"NIBArchive" + struct.pack(
        "<10I", 1, 1,
        len(objects), offset,
        len(keys), offset + len(obj_bytes),
        len(values), offset + len(obj_bytes) + len(key_bytes),
        len(classes), offset + len(obj_bytes) + len(key_bytes) + len(value_bytes))
    with open(path, "wb") as f:
        f.write(header + obj_bytes + key_bytes + value_bytes + class_bytes)
