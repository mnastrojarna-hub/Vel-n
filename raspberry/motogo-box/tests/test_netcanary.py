"""Síťový canary update.sh (scripts/lib/netcanary.sh): internet OK před → FAIL po = rollback profilů + značka."""
import os
import shutil
import subprocess
import textwrap
from pathlib import Path

import pytest

LIB = Path(__file__).resolve().parents[1] / "scripts" / "lib" / "netcanary.sh"
pytestmark = pytest.mark.skipif(shutil.which("bash") is None, reason="bash")


def _run(tmp_path: Path, probe_codes: list[str], nmcli_ok: bool = True) -> tuple[subprocess.CompletedProcess, Path, Path]:
    fake = tmp_path / "bin"
    fake.mkdir()
    seq = tmp_path / "probe_seq"
    seq.write_text("\n".join(probe_codes) + "\n")
    # falešný curl: každé volání vrátí další kód ze seznamu (poslední se opakuje)
    (fake / "curl").write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        f="{seq}"; code="$(head -n1 "$f")"; rest="$(tail -n +2 "$f")"
        [[ -n "$rest" ]] && printf '%s\\n' "$rest" > "$f"
        printf '%s' "$code"
        """))
    (fake / "timeout").write_text("#!/usr/bin/env bash\nexit 1\n")           # TCP fallback vždy selže
    (fake / "nmcli").write_text(f"#!/usr/bin/env bash\necho \"$@\" >> {tmp_path}/nmcli.log\nexit {0 if nmcli_ok else 1}\n")
    (fake / "install").write_text("#!/usr/bin/env bash\ncp \"${@: -2:1}\" \"${@: -1}\"\n")
    for f in fake.iterdir():
        f.chmod(0o755)
    prof = tmp_path / "profiles"
    prof.mkdir()
    (prof / "motogo-lan.nmconnection").write_text("ORIGINAL-LAN\n")
    (prof / "motogo-lte.nmconnection").write_text("ORIGINAL-LTE\n")
    state, marker = tmp_path / "state", tmp_path / "net_rollback"
    script = f"""
        source "{LIB}"
        netcanary_begin
        echo "CHANGED-LAN" > "{prof}/motogo-lan.nmconnection"
        netcanary_end
        echo "before=$NETCANARY_BEFORE"
    """
    env = {**os.environ, "PATH": f"{fake}:{os.environ['PATH']}", "NETCANARY_SLEEP": "0",
           "NETCANARY_PROFILE_DIR": str(prof), "NETCANARY_STATE_DIR": str(state), "NETCANARY_MARKER": str(marker)}
    res = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, timeout=60)
    return res, prof, marker


def test_rollback_when_internet_lost_after_changes(tmp_path):
    res, prof, marker = _run(tmp_path, ["204", "000", "000", "000", "204"])
    assert res.returncode == 0, res.stderr + res.stdout
    assert "before=ok" in res.stdout and "vracím profily" in res.stdout
    assert (prof / "motogo-lan.nmconnection").read_text() == "ORIGINAL-LAN\n"     # vráceno ze zálohy
    assert marker.exists() and '"internet_after_rollback":"ok"' in marker.read_text()
    log = (tmp_path / "nmcli.log").read_text()
    assert "con reload" in log and "con up motogo-lan" in log and "con up motogo-lte" in log


def test_no_rollback_when_internet_ok_or_was_down_before(tmp_path):
    res, prof, marker = _run(tmp_path, ["204", "204"])
    assert res.returncode == 0 and (prof / "motogo-lan.nmconnection").read_text() == "CHANGED-LAN\n"
    assert not marker.exists()
    res, prof, marker = _run(tmp_path / "b" if (tmp_path / "b").mkdir() is None else tmp_path, ["000", "000", "000", "000"])
    assert res.returncode == 0 and "before=fail" in res.stdout
    assert (prof / "motogo-lan.nmconnection").read_text() == "CHANGED-LAN\n" and not marker.exists()
