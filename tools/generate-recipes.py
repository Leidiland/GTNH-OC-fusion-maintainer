"""Generate recipes.lua from GT5-Unofficial and NewHorizonsCoreMod source checkouts.

Usage: python tools/generate-recipes.py <GT5-Unofficial path> [<NewHorizonsCoreMod path> ...] [--output recipes.lua] [--label "..."]
"""

import argparse
import pathlib
import re
import subprocess
import sys

STATE_BY_GETTER = {"getGas": "GAS", "getFluid": "LIQUID", "getPlasma": "PLASMA", "getMolten": "MOLTEN"}
VOLTAGE_TIERS = ["ULV", "LV", "MV", "HV", "EV", "IV", "LuV", "ZPM", "UV", "UHV", "UEV", "UIV", "UMV", "UXV", "MAX"]
SANITIZED_CHARACTERS = " -_?!@#(){}[]"


class UnresolvedFluid(Exception):
    pass


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    lines = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for index, character in enumerate(line):
            if character == '"' and (index == 0 or line[index - 1] != "\\"):
                in_string = not in_string
            elif not in_string and line.startswith("//", index):
                cut = index
                break
        lines.append(line[:cut])
    return "\n".join(lines)


def split_arguments(text):
    arguments, depth, current = [], 0, []
    in_string = False
    for character in text:
        if character == '"':
            in_string = not in_string
        if not in_string:
            if character in "([{":
                depth += 1
            elif character in ")]}":
                depth -= 1
            elif character == "," and depth == 0:
                arguments.append("".join(current).strip())
                current = []
                continue
        current.append(character)
    if "".join(current).strip():
        arguments.append("".join(current).strip())
    return arguments


def call_arguments(body, method):
    match = re.search(r"\." + method + r"\(", body)
    if match is None:
        return None
    depth, index = 1, match.end()
    while depth and index < len(body):
        depth += {"(": 1, ")": -1}.get(body[index], 0)
        index += 1
    return split_arguments(body[match.end():index - 1])


def sanitize(text):
    return "".join(character for character in text if character not in SANITIZED_CHARACTERS)


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


class Sources:
    def __init__(self, roots):
        self.files = {}
        self.locations = {}
        for root in roots:
            for path in (root / "src" / "main" / "java").rglob("*.java"):
                self.files[path] = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
                self.locations[path] = root.name + "/" + path.relative_to(root).as_posix()

    def find(self, suffix):
        for path, text in self.files.items():
            if path.as_posix().endswith(suffix):
                return text
        raise FileNotFoundError(suffix)


class Numbers:
    def __init__(self, sources):
        self.values = {}
        builder = sources.find("gregtech/api/util/GTRecipeBuilder.java")
        for name, expression in re.findall(r"public static final int (\w+)\s*=\s*([^;]+);", builder):
            try:
                self.values[name] = self.evaluate(expression)
            except Exception:
                pass

        values = sources.find("gregtech/api/enums/GTValues.java")
        voltages = re.search(r"long\[\]\s+V\s*=\s*new long\[\]\s*\{(.*?)\};", values, re.S).group(1)
        voltages = [self.evaluate(item) for item in split_arguments(voltages)]
        for index, tier in enumerate(VOLTAGE_TIERS):
            self.values["TierEU." + tier] = voltages[index]
            self.values["TierEU.RECIPE_" + tier] = voltages[index] * 30 // 32

    def evaluate(self, expression):
        expression = expression.replace("Integer.MAX_VALUE", "2147483647")
        expression = re.sub(r"(\d)_(?=\d)", r"\1", expression)
        expression = re.sub(r"(\d+)[lL]\b", r"\1", expression)
        expression = re.sub(r"\(\s*(int|long)\s*\)", "", expression)
        for name in sorted(self.values, key=len, reverse=True):
            expression = re.sub(r"(?<![\w.])" + re.escape(name) + r"(?![\w])", str(self.values[name]), expression)
        expression = expression.replace("/", "//")
        if not re.fullmatch(r"[\d\s+\-*/()]+", expression):
            raise ValueError("Cannot evaluate " + expression)
        return int(eval(expression, {"__builtins__": {}}))


class Fluids:
    def __init__(self, sources):
        self.gregtech = {}
        self.explicit = {}
        self.werkstoffs = {}
        self.gtpp = {}

        loaders = {}
        for text in sources.files.values():
            for loader, body in re.findall(r"private static Materials (load\w+)\(\)\s*\{(.*?)\bconstructMaterial\(\)", text, re.S):
                name = re.search(r'setName\("([^"]+)"\)', body)
                label = re.search(r'setDefaultLocalName\("([^"]+)"\)', body)
                if name:
                    loaders[loader] = {
                        "name": name.group(1),
                        "label": label.group(1) if label else name.group(1),
                        "plasma": ".addPlasma()" in body,
                        "fluid": ".addFluid()" in body or ".addGas()" in body
                    }
        for text in sources.files.values():
            for field, loader in re.findall(r"Materials\.(\w+)\s*=\s*(load\w+)\(\)", text):
                if loader in loaders:
                    self.gregtech[field] = loaders[loader]

        for text in sources.files.values():
            for name, chain in re.findall(r'GTFluidFactory\s*\.builder\("([^"]+)"\)(.*?);', text, re.S):
                material = re.search(r"configureMaterials\(Materials\.(\w+)\)", chain)
                if material is None:
                    continue
                state = re.search(r"withStateAndTemperature\(\s*(?:FluidState\.)?(\w+)", chain)
                label = re.search(r'withDefaultLocalName\(\s*"([^"]*)"', chain)
                state = state.group(1) if state else "LIQUID"
                state = state if state in ("GAS", "PLASMA", "MOLTEN", "SLURRY") else "LIQUID"
                material = material.group(1)
                gregtech = self.gregtech.get(material)
                self.explicit[(material, state)] = (
                    name.lower(),
                    label.group(1) if label else (gregtech["label"] if gregtech else name)
                )

        for suffix, owner in (("bartworks/system/material/WerkstoffLoader.java", "WerkstoffLoader"),
                              ("goodgenerator/items/GGMaterial.java", "GGMaterial")):
            text = sources.find(suffix)
            for match in re.finditer(r"public static final Werkstoff (\w+)\s*=\s*new Werkstoff\(", text):
                literal = re.search(r'"([^"]+)"', text[match.end():match.end() + 400])
                if literal:
                    self.werkstoffs[(owner, match.group(1))] = literal.group(1)

        for suffix in ("gtPlusPlus/core/material/MaterialsElements.java", "gtPlusPlus/core/material/MaterialsAlloy.java"):
            text = sources.find(suffix)
            pattern = r"\bMaterial (\w+)\s*=\s*new Material\(\s*\"([^\"]+)\"\s*,\s*(?:\"([^\"]+)\"\s*,\s*)?MaterialState\.(\w+)"
            for field, name, label, state in re.findall(pattern, text):
                self.gtpp[field] = {"name": name, "label": label or name, "state": state}

    def gregtech_by_name(self, name):
        candidates = {name.lower(), name.replace(" ", "_").lower(), name.replace(" ", "").lower()}
        for material in self.gregtech.values():
            if material["name"].lower() in candidates:
                return material
        return None

    def gregtech_fluid(self, field, getter):
        state = STATE_BY_GETTER[getter]
        if (field, state) in self.explicit:
            return self.explicit[(field, state)]
        material = self.gregtech.get(field)
        if material is None:
            raise UnresolvedFluid("Materials." + field)
        name = material["name"].lower()
        if state == "PLASMA":
            return "plasma." + name, material["label"] + " Plasma"
        if state == "MOLTEN":
            return "molten." + name, "Molten " + material["label"]
        return name, material["label"]

    def werkstoff_fluid(self, owner, field, getter):
        name = self.werkstoffs.get((owner, field))
        if name is None:
            raise UnresolvedFluid(owner + "." + field)
        if getter == "getMolten":
            return "molten." + name.lower(), "Molten " + name
        return name.lower(), name

    def gtpp_material(self, field):
        material = self.gtpp.get(field)
        if material is None:
            raise UnresolvedFluid("GT++ " + field)
        return material

    def gtpp_fluid(self, field):
        material = self.gtpp_material(field)
        equivalent = self.gregtech_by_name(material["label"])
        if equivalent is not None:
            if equivalent["fluid"]:
                return equivalent["name"].lower(), equivalent["label"]
            return "molten." + equivalent["name"].lower(), "Molten " + equivalent["label"]
        name = sanitize(material["name"]).lower()
        if material["state"] in ("GAS", "PURE_GAS"):
            return name, material["label"]
        if material["state"] in ("LIQUID", "PURE_LIQUID"):
            return "molten." + name, material["label"]
        return "molten." + name, "Molten " + material["label"]

    def gtpp_plasma(self, field):
        material = self.gtpp_material(field)
        equivalent = self.gregtech_by_name(material["label"])
        if equivalent is not None and equivalent["plasma"]:
            return "plasma." + equivalent["name"].lower(), equivalent["label"] + " Plasma"
        return "plasma." + sanitize(material["label"]).lower(), material["label"] + " Plasma"

    def resolve(self, expression, numbers):
        expression = expression.strip()

        match = re.fullmatch(r"(?:Materials\.)?(\w+)\.(getGas|getFluid|getPlasma|getMolten)\((.+)\)", expression, re.S)
        if match:
            return self.gregtech_fluid(match.group(1), match.group(2)) + (numbers.evaluate(match.group(3)),)

        match = re.fullmatch(r"(WerkstoffLoader|GGMaterial)\.(\w+)\.(getMolten|getFluidOrGas)\((.+)\)", expression, re.S)
        if match:
            return self.werkstoff_fluid(match.group(1), match.group(2), match.group(3)) + (numbers.evaluate(match.group(4)),)

        match = re.fullmatch(r"(?:MaterialsElements\.(?:getInstance\(\)|STANDALONE)|MaterialsAlloy)\.(\w+)\.getFluidStack\((.+)\)", expression, re.S)
        if match:
            return self.gtpp_fluid(match.group(1)) + (numbers.evaluate(match.group(2)),)

        match = re.fullmatch(r"FluidRegistry\.getFluidStack\(\s*\"([^\"]+)\"\s*,(.+)\)", expression, re.S)
        if match:
            return match.group(1), match.group(1), numbers.evaluate(match.group(2))

        match = re.fullmatch(r"new FluidStack\((.+)\)", expression, re.S)
        if match:
            fluid, amount = split_arguments(match.group(1))
            amount = numbers.evaluate(amount)
            inner = re.fullmatch(r"(?:MaterialsElements\.(?:getInstance\(\)|STANDALONE)|MaterialsAlloy)\.(\w+)\.(getPlasma|getFluid)\(\)", fluid)
            if inner:
                resolved = self.gtpp_plasma(inner.group(1)) if inner.group(2) == "getPlasma" else self.gtpp_fluid(inner.group(1))
                return resolved + (amount,)
            inner = re.fullmatch(r"FluidRegistry\.getFluid\(\s*\"([^\"]+)\"\s*\)", fluid)
            if inner:
                return inner.group(1), inner.group(1), amount

        raise UnresolvedFluid(expression)


def extract_recipes(sources, numbers, fluids):
    recipes, errors = [], []
    for path, text in sorted(sources.files.items()):
        for match in re.finditer(r"\.addTo\(\s*fusionRecipes\s*\)", text):
            start = text.rfind("GTValues.RA.stdBuilder()", 0, match.start())
            body = text[start:match.start()]
            location = "{}:{}".format(sources.locations[path], text.count("\n", 0, start) + 1)
            try:
                inputs = [fluids.resolve(argument, numbers) for argument in call_arguments(body, "fluidInputs") or []]
                outputs = [fluids.resolve(argument, numbers) for argument in call_arguments(body, "fluidOutputs") or []]
                threshold = call_arguments(body, "metadata")
                if len(outputs) != 1 or threshold is None or "FUSION_THRESHOLD" not in threshold[0]:
                    raise UnresolvedFluid("unexpected recipe shape")
                recipes.append({
                    "output": outputs[0],
                    "inputs": inputs,
                    "startupEu": numbers.evaluate(threshold[1]),
                    "eut": numbers.evaluate(call_arguments(body, "eut")[0]),
                    "duration": numbers.evaluate(call_arguments(body, "duration")[0])
                })
            except (UnresolvedFluid, ValueError, TypeError) as exception:
                errors.append("{}: {}".format(location, exception))
    return recipes, errors


def fluid_lua(fluid):
    name, label, amount = fluid
    return "{{name = {}, label = {}, amount = {}}}".format(lua_string(name), lua_string(label), amount)


def write_lua(recipes, output, label):
    recipes.sort(key=lambda recipe: (recipe["output"][1], recipe["startupEu"], [fluid[0] for fluid in recipe["inputs"]]))
    lines = ["-- Generated by tools/generate-recipes.py from " + label, "return {"]
    for index, recipe in enumerate(recipes):
        lines.append("  {")
        lines.append("    output = " + fluid_lua(recipe["output"]) + ",")
        lines.append("    inputs = {" + ", ".join(fluid_lua(fluid) for fluid in recipe["inputs"]) + "},")
        lines.append("    startupEu = {}, eut = {}, duration = {}".format(recipe["startupEu"], recipe["eut"], recipe["duration"]))
        lines.append("  }" + ("," if index < len(recipes) - 1 else ""))
    lines.append("}")
    output.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def detect_version(root):
    try:
        result = subprocess.run(["git", "-C", str(root), "describe", "--tags"], capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def main():
    parser = argparse.ArgumentParser(description="Generate the fusion recipe table from GT5-Unofficial and NewHorizonsCoreMod sources")
    parser.add_argument("sources", type=pathlib.Path, nargs="+", help="Path to a GT5-Unofficial checkout, followed by other checkouts that add fusion recipes")
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent.parent / "recipes.lua")
    parser.add_argument("--label", help="Source description written to the file header")
    arguments = parser.parse_args()

    sources = Sources(arguments.sources)
    numbers = Numbers(sources)
    fluids = Fluids(sources)
    recipes, errors = extract_recipes(sources, numbers, fluids)

    for error in errors:
        print("error:", error, file=sys.stderr)

    if errors:
        return 1

    label = arguments.label or ", ".join(root.name + " " + detect_version(root) for root in arguments.sources)
    write_lua(recipes, arguments.output, label)
    print("Wrote {} recipes to {}".format(len(recipes), arguments.output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
