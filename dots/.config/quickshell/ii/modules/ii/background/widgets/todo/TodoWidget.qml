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

    implicitWidth: 530
    implicitHeight: 320

    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    property string selectedDateString: CalendarLayout.getTodayDateString()

    function getTaskCountForDate(dateStr) {
        if (!Todo.list) return 0;
        const todayStr = CalendarLayout.getTodayDateString();
        return Todo.list.filter(t => !t.done && ((t.date === dateStr) || (!t.date && dateStr === todayStr))).length;
    }

    readonly property var selectedDateTasks: {
        if (!Todo.list) return [];
        const todayStr = CalendarLayout.getTodayDateString();
        return Todo.list
            .map((item, index) => Object.assign({}, item, { originalIndex: index }))
            .filter(item => {
                if (item.date) return item.date === root.selectedDateString;
                return root.selectedDateString === todayStr;
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
        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // ================= LEFT: CALENDAR COLUMN =================
            ColumnLayout {
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                spacing: 6

                // Month navigation row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        text: `${root.monthShift !== 0 ? "• " : ""}${root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                        font.pixelSize: Appearance.font.pixelSize.medium
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
                                taskCount: root.getTaskCountForDate(cellData.dateString)

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
                color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)
            }

            // ================= RIGHT: DAY AGENDA COLUMN =================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // Header for selected day
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            text: root.getFormattedDateTitle(root.selectedDateString)
                            font.pixelSize: Appearance.font.pixelSize.medium
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                            elide: Text.ElideRight
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
                        implicitWidth: badgeText.implicitWidth + 12
                        implicitHeight: 22
                        radius: Appearance.rounding.full
                        color: root.remainingCount > 0 ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85) : Appearance.colors.colLayer2

                        StyledText {
                            id: badgeText
                            anchors.centerIn: parent
                            text: root.remainingCount > 0 ? `${root.remainingCount} pending` : "Done 🎉"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: root.remainingCount > 0 ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
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
                        spacing: 4

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "event_available"
                            iconSize: 32
                            color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("No tasks for this day")
                            font.pixelSize: Appearance.font.pixelSize.small
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

                        delegate: Rectangle {
                            id: taskRow
                            required property var modelData
                            width: taskListView.width
                            height: 34
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
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 8

                                // Toggle checkbox
                                MouseArea {
                                    implicitWidth: 20
                                    implicitHeight: 20
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
                                        iconSize: 18
                                        color: taskRow.modelData.done ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                                    }
                                }

                                // Task content
                                StyledText {
                                    Layout.fillWidth: true
                                    text: taskRow.modelData.content
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.strikeout: taskRow.modelData.done
                                    color: taskRow.modelData.done ? Appearance.colors.colOutlineVariant : Appearance.colors.colOnLayer0
                                }

                                // Delete button
                                RippleButton {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: Appearance.rounding.verysmall
                                    visible: rowMouseArea.containsMouse
                                    onClicked: Todo.deleteItem(taskRow.modelData.originalIndex)

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 14
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
                    height: 36
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: taskTextInput.activeFocus ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 6

                        MaterialSymbol {
                            text: "add_task"
                            iconSize: 16
                            color: Appearance.colors.colOutlineVariant
                        }

                        TextInput {
                            id: taskTextInput
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.small
                            clip: true
                            onAccepted: addTask()

                            StyledText {
                                anchors.fill: parent
                                visible: taskTextInput.text.length === 0 && !taskTextInput.activeFocus
                                text: Translation.tr("Add task for this day...")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOutlineVariant
                            }
                        }

                        RippleButton {
                            implicitWidth: 26
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.verysmall
                            enabled: taskTextInput.text.trim().length > 0
                            onClicked: addTask()

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_upward"
                                iconSize: 16
                                color: taskTextInput.text.trim().length > 0 ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            }
                        }
                    }

                    function addTask() {
                        const trimmed = taskTextInput.text.trim();
                        if (trimmed.length > 0) {
                            Todo.addTask(trimmed, root.selectedDateString);
                            taskTextInput.text = "";
                        }
                    }
                }
            }
        }
    }
}
