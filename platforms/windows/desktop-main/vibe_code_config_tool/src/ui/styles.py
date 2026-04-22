"""
QSS 样式定义
"""

CONNECTION_BAR_STYLE = """
QFrame#connectionBar {
    border-bottom: 1px solid #3a3a3a;
    padding: 4px;
}
"""

MODE_SELECTOR_STYLE = """
QPushButton.modeBtn {
    padding: 8px 24px;
    border: none;
    border-bottom: 2px solid transparent;
    font-size: 13px;
    font-weight: bold;
}
QPushButton.modeBtn:checked {
    border-bottom: 2px solid #4fc3f7;
    color: #4fc3f7;
}
QPushButton.modeBtn:hover {
    background-color: rgba(255, 255, 255, 0.05);
}
"""

KEY_BUTTON_STYLE = """
QPushButton.keyBtn {
    min-width: 100px;
    min-height: 80px;
    font-size: 14px;
    font-weight: bold;
    border: 2px solid #555;
    border-radius: 8px;
    background-color: #2d2d2d;
}
QPushButton.keyBtn:hover {
    border-color: #4fc3f7;
    background-color: #353535;
}
QPushButton.keyBtn:checked {
    border-color: #4fc3f7;
    background-color: #1a3a4a;
}
"""

DEVICE_INFO_STYLE = """
QLabel.infoLabel {
    font-size: 12px;
    color: #aaa;
}
QLabel.infoValue {
    font-size: 13px;
    font-weight: bold;
}
"""
