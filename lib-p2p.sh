#!/bin/bash
#################################################################################
# Funções compartilhadas de Wi-Fi P2P (usadas por all.sh e all-dual.sh).
#
# O chip Wi-Fi do Raspberry Pi 5 (brcmfmac) aceita UM grupo P2P-GO por vez
# (#{ P2P-client, P2P-GO } <= 1). Se uma interface p2p-wl* sobra no kernel sem
# que o wpa_supplicant a conheça (órfã), ela ocupa essa vaga e todo p2p_group_add
# seguinte falha com "iface validation failed: err=-16" (Device or resource busy).
# O all.sh só procurava grupos listados pelo wpa_cli e repetia a tentativa para sempre.
#################################################################################

# Remove interfaces p2p-wl* presentes no kernel e ausentes do wpa_supplicant.
cleanup_orphan_p2p_ifaces() {
    command -v iw >/dev/null 2>&1 || return 0
    local known kif
    known="$(sudo wpa_cli interface 2>/dev/null)"
    for kif in $(iw dev 2>/dev/null | awk '/Interface p2p-wl/ {print $2}'); do
        if ! echo "$known" | grep -qx "$kif"; then
            echo "Removendo interface P2P órfã do kernel: $kif"
            sudo iw dev "$kif" del 2>/dev/null
        fi
    done
}
