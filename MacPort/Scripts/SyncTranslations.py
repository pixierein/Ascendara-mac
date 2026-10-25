import concurrent.futures as Futures
import json as JSON
from pathlib import Path
import re as Regex
import urllib.request as Request

Root = Path(__file__).resolve().parents[1]


def Fetch(Address):
    RequestValue = Request.Request(Address, headers={"User-Agent": "Ascendara-Native-Translations"})
    with Request.urlopen(RequestValue, timeout=45) as Response:
        return Response.read()


def Main():
    Commit = JSON.loads(Fetch("https://api.github.com/repos/Ascendara/ascendara/commits/main"))["sha"]
    Base = f"https://raw.githubusercontent.com/Ascendara/ascendara/{Commit}/"
    Destination = Root / "Source/Ascendara/Resources/Translations"
    Destination.mkdir(parents=True, exist_ok=True)
    Languages = []
    Pattern = r'\s*(?:"([^"]+)"|([\w-]+)):\s*\{ name: "([^"]+)", nativeName: "([^"]+)" \}'
    for PathValue, Bundled in [("src/i18n.js", True), ("src/lib/extraLanguages.js", False)]:
        Source = Fetch(Base + PathValue).decode()
        for Quoted, Bare, Name, Native in Regex.findall(Pattern, Source):
            Languages.append({"id": Quoted or Bare, "name": Name, "nativeName": Native, "bundled": Bundled})

    def Download(Language):
        Code = Language["id"]
        Data = Fetch(Base + f"src/translations/{Code}.json")
        Document = JSON.loads(Data)
        assert isinstance(Document, dict) and Document
        (Destination / f"{Code}.json").write_text(JSON.dumps(Document, ensure_ascii=False, indent=2) + "\n")

    with Futures.ThreadPoolExecutor(max_workers=4) as Pool:
        list(Pool.map(Download, [Language for Language in Languages if Language["bundled"]]))
    (Destination / "Languages.json").write_text(JSON.dumps({"commit": Commit, "languages": Languages}, ensure_ascii=False, indent=2) + "\n")
    (Destination / "TranslationSource.txt").write_text(
        f"Ascendara i18next translations, MIT licensed.\nSource: https://github.com/Ascendara/ascendara/tree/{Commit}/src/translations\n"
        "The optional language catalogue describes upstream's generated languages. Import their i18next JSON files to enable them.\n")
    print(f"Imported {sum(Language['bundled'] for Language in Languages)} dictionaries and {len(Languages)} language names at {Commit}.")


if __name__ == "__main__":
    Main()
