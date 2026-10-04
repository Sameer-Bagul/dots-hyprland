pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets
import "calendar_layout.js" as CalendarLayout

AbstractBackgroundWidget {
    id: root

    configEntryName: "todo"
    needsColText: true

    property bool showCalendar: false

    implicitWidth: showCalendar ? 635 : 410
    implicitHeight: 360

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    property string selectedDateString: CalendarLayout.getTodayDateString()

    function getTaskCountForDate(dateStr, list) {
        if (!list) return 0;
        const todayStr = CalendarLayout.getTodayDateString();
        return list.filter(t => !t.done && ((t.date === dateStr) || (!t.date && dateStr === todayStr))).length;
    }

    function addTask(text) {
        const trimmed = (text ?? "").trim();
        if (trimmed.length > 0) {
            Todo.addTask(trimmed, root.selectedDateString);
            taskTextField.text = "";
        }
    }

    readonly property var selectedDateTasks: {
        if (!Todo.list) return [];
        const todayStr = CalendarLayout.getTodayDateString();
        return Todo.list
            .map((item, index) => Object.assign({}, item, { originalIndex: index }))
            .filter(item => {
                if (item.date) return item.date === root.selectedDateString;
                return root.selectedDateString === todayStr;
            })
            .sort((a, b) => {
                if (a.done !== b.done) {
                    return a.done ? 1 : -1;
                }
                return a.originalIndex - b.originalIndex;
            });
    }

    readonly property int remainingCount: selectedDateTasks.filter(t => !t.done).length

    function getFormattedDateTitle(dateStr) {
        if (!dateStr) return "";
        const todayStr = CalendarLayout.getTodayDateString();
        if (dateStr === todayStr) return Translation.tr("Today");

        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        const tomorrowStr = CalendarLayout.formatDateKey(tomorrow.getFullYear(), tomorrow.getMonth() + 1, tomorrow.getDate());
        if (dateStr === tomorrowStr) return Translation.tr("Tomorrow");

        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        const yesterdayStr = CalendarLayout.formatDateKey(yesterday.getFullYear(), yesterday.getMonth() + 1, yesterday.getDate());
        if (dateStr === yesterdayStr) return Translation.tr("Yesterday");

        const parts = dateStr.split("-").map(p => parseInt(p, 10));
        const d = new Date(parts[0], parts[1] - 1, parts[2]);
        return d.toLocaleDateString(Qt.locale(), "dddd");
    }

    function getFormattedDateSubtitle(dateStr) {
        if (!dateStr) return "";
        const parts = dateStr.split("-").map(p => parseInt(p, 10));
        const d = new Date(parts[0], parts[1] - 1, parts[2]);
        return d.toLocaleDateString(Qt.locale(), "MMMM d, yyyy");
    }

    // Shadow
    StyledRectangularShadow {
        target: backgroundCard
        radius: backgroundCard.radius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }

    // Main Card
    Rectangle {
        id: backgroundCard
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.large
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: root.showCalendar ? 14 : 0

            // ================= LEFT: COLLAPSIBLE CALENDAR =================
            ColumnLayout {
                id: calendarPane
                Layout.preferredWidth: root.showCalendar ? 220 : 0
                Layout.fillHeight: true
                visible: opacity > 0
                opacity: root.showCalendar ? 1 : 0
                clip: true

                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                // Month navigation row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.monthShift !== 0 ? "• " : ""}${root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: root.monthShift !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.monthShift !== 0) {
                                    root.monthShift = 0;
                                    root.selectedDateString = CalendarLayout.getTodayDateString();
                                }
                            }
                        }
                    }

                    // Jump to today if shifted
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.verysmall
                        visible: root.monthShift !== 0
                        onClicked: {
                            root.monthShift = 0;
                            root.selectedDateString = CalendarLayout.getTodayDateString();
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "today"
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }
                    }

                    // Prev month
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.verysmall
                        onClicked: root.monthShift--
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_left"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    // Next month
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.verysmall
                        onClicked: root.monthShift++
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_right"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                // Weekday headers
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    Repeater {
                        model: CalendarLayout.weekDays
                        delegate: CalendarDayCell {
                            day: Translation.tr(modelData.day)
                            isWeekdayHeader: true
                            isBold: true
                        }
                    }
                }

                // 6-Row Calendar Grid
                Repeater {
                    model: 6
                    delegate: RowLayout {
                        id: weekRow
                        required property int modelData
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4

                        Repeater {
                            model: 7
                            delegate: CalendarDayCell {
                                required property int index
                                readonly property var cellData: root.calendarLayout[weekRow.modelData][index]

                                day: String(cellData.day)
                                dateString: cellData.dateString
                                isToday: cellData.today
                                isSelected: cellData.dateString === root.selectedDateString
                                taskCount: root.getTaskCountForDate(cellData.dateString, Todo.list)

                                onClicked: {
                                    root.selectedDateString = cellData.dateString;
                                }
                            }
                        }
                    }
                }
            }

            // ================= VERTICAL DIVIDER =================
            Rectangle {
                Layout.fillHeight: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                width: 1
                visible: root.showCalendar
                opacity: root.showCalendar ? 1 : 0
                color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }
            }

            // ================= RIGHT: DAY AGENDA / TODO COLUMN =================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Header for selected day
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        RowLayout {
                            spacing: 6

                            StyledText {
                                text: root.getFormattedDateTitle(root.selectedDateString)
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                                elide: Text.ElideRight
                            }

                            // Return to Today chip if viewing another date
                            RippleButton {
                                implicitWidth: 24
                                implicitHeight: 24
                                buttonRadius: Appearance.rounding.verysmall
                                visible: root.selectedDateString !== CalendarLayout.getTodayDateString()
                                onClicked: {
                                    root.selectedDateString = CalendarLayout.getTodayDateString();
                                    root.monthShift = 0;
                                }
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "today"
                                    iconSize: 16
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }

                        StyledText {
                            text: root.getFormattedDateSubtitle(root.selectedDateString)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOutlineVariant
                            elide: Text.ElideRight
                        }
                    }

                    // Task count chip
                    Rectangle {
                        implicitWidth: badgeText.implicitWidth + 14
                        implicitHeight: 24
                        radius: Appearance.rounding.full
                        color: root.remainingCount > 0 ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85) : Appearance.colors.colLayer2

                        StyledText {
                            id: badgeText
                            anchors.centerIn: parent
                            text: root.remainingCount > 0 ? `${root.remainingCount} pending` : Translation.tr("All done")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: root.remainingCount > 0 ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                        }
                    }

                    // Calendar toggle button
                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.verysmall
                        toggled: root.showCalendar
                        onClicked: root.showCalendar = !root.showCalendar

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.showCalendar ? "calendar_today" : "calendar_month"
                            iconSize: 18
                            color: root.showCalendar ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        }
                    }
                }

                // Tasks list
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // Empty state
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: root.selectedDateTasks.length === 0
                        spacing: 6

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "event_available"
                            iconSize: 36
                            color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("No tasks for this day")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOutlineVariant
                        }
                    }

                    // Task List View
                    ListView {
                        id: taskListView
                        anchors.fill: parent
                        spacing: 4
                        model: root.selectedDateTasks
                        boundsBehavior: Flickable.StopAtBounds
                        displaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                            }
                        }

                        delegate: Rectangle {
                            id: taskRow
                            required property var modelData
                            width: taskListView.width
                            implicitHeight: Math.max(38, taskRowLayout.implicitHeight + 8)
                            radius: Appearance.rounding.small
                            color: rowMouseArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            MouseArea {
                                id: rowMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            RowLayout {
                                id: taskRowLayout
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10

                                // Toggle checkbox
                                MouseArea {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (taskRow.modelData.done) {
                                            Todo.markUnfinished(taskRow.modelData.originalIndex);
                                        } else {
                                            Todo.markDone(taskRow.modelData.originalIndex);
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: taskRow.modelData.done ? "check_circle" : "radio_button_unchecked"
                                        iconSize: 20
                                        color: taskRow.modelData.done ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                                    }
                                }

                                // Task content
                                StyledText {
                                    Layout.fillWidth: true
                                    text: taskRow.modelData.content
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.strikeout: taskRow.modelData.done
                                    color: taskRow.modelData.done ? Appearance.colors.colOutlineVariant : Appearance.colors.colOnLayer0
                                }

                                // Delete button
                                RippleButton {
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    buttonRadius: Appearance.rounding.verysmall
                                    visible: rowMouseArea.containsMouse
                                    onClicked: Todo.deleteItem(taskRow.modelData.originalIndex)

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 16
                                        color: Appearance.colors.colOutlineVariant
                                    }
                                }
                            }
                        }
                    }
                }

                // Quick Add Input Box
                Rectangle {
                    Layout.fillWidth: true
                    height: 42
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: taskTextField.activeFocus ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 6

                        MaterialSymbol {
                            text: "add_task"
                            iconSize: 18
                            color: Appearance.colors.colOutlineVariant
                        }

                        TextField {
                            id: taskTextField
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.normal
                            placeholderText: Translation.tr("Add task...")
                            placeholderTextColor: Appearance.colors.colOutlineVariant
                            selectByMouse: true
                            activeFocusOnTab: true
                            clip: true
                            background: null
                            onAccepted: root.addTask(taskTextField.text)
                        }

                        RippleButton {
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.verysmall
                            enabled: taskTextField.text.trim().length > 0
                            onClicked: root.addTask(taskTextField.text)

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_upward"
                                iconSize: 18
                                color: taskTextField.text.trim().length > 0 ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
