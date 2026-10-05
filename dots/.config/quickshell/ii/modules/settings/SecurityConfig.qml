import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.functions as CF
import qs.modules.common.widgets

Item {
    id: root

    property bool showEnrollDialog: false
    property string selectedFingerToEnroll: "right-index-finger"

    property string currentPasswordInput: ""
    property string newPasswordInput: ""
    property string confirmPasswordInput: ""
    property bool showCurrentPassword: false
    property bool showNewPassword: false
    property bool showConfirmPassword: false

    property string deleteConfirmFinger: ""
    property bool showDeleteDialog: false

    Component.onCompleted: {
        SecurityService.refresh();
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: true

        // ================= 1. USER OVERVIEW SECTION =================
        ContentSection {
            icon: "manage_accounts"
            title: Translation.tr("User Account")

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: userOverviewLayout.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: userOverviewLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 14

                    // User Avatar
                    Rectangle {
                        implicitWidth: 48
                        implicitHeight: 48
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "person"
                            iconSize: 28
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: SystemInfo.username
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }

                        RowLayout {
                            spacing: 8

                            // Fingerprint status chip
                            Rectangle {
                                implicitWidth: fpChipText.implicitWidth + 12
                                implicitHeight: 20
                                radius: Appearance.rounding.full
                                color: SecurityService.enrolledFingers.length > 0
                                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                                    : Appearance.colors.colLayer2

                                StyledText {
                                    id: fpChipText
                                    anchors.centerIn: parent
                                    text: SecurityService.enrolledFingers.length > 0
                                        ? Translation.tr("%1 Fingerprint(s) Enrolled").arg(SecurityService.enrolledFingers.length)
                                        : Translation.tr("No Fingerprints Enrolled")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: SecurityService.enrolledFingers.length > 0
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colOutlineVariant
                                }
                            }

                            // Password status chip
                            Rectangle {
                                implicitWidth: passChipText.implicitWidth + 12
                                implicitHeight: 20
                                radius: Appearance.rounding.full
                                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)

                                StyledText {
                                    id: passChipText
                                    anchors.centerIn: parent
                                    text: Translation.tr("Password Protected")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= 2. FINGERPRINT AUTHENTICATION =================
        ContentSection {
            icon: "fingerprint"
            title: Translation.tr("Fingerprint Authentication")

            // Hardware Device Info Banner
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: devInfoLayout.implicitHeight + 16
                radius: Appearance.rounding.small
                color: SecurityService.available
                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.9)
                border.width: 1
                border.color: SecurityService.available
                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)
                    : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

                RowLayout {
                    id: devInfoLayout
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    MaterialSymbol {
                        text: SecurityService.available ? "sensors" : "sensors_off"
                        iconSize: 22
                        color: SecurityService.available ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            text: SecurityService.available ? SecurityService.deviceName : Translation.tr("No fingerprint sensor detected")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            text: SecurityService.available
                                ? Translation.tr("Type: %1 sensor • %2 enrollment stages • Driver: fprintd").arg(SecurityService.scanType).arg(SecurityService.numStages)
                                : Translation.tr("Connect a supported fingerprint reader to enable biometric authentication.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOutlineVariant
                        }
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.verysmall
                        onClicked: SecurityService.refresh()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledToolTip { text: Translation.tr("Refresh device status") }
                    }
                }
            }

            // List of Enrolled Fingerprints
            ContentSubsection {
                title: Translation.tr("Enrolled Fingerprints")
                visible: SecurityService.available

                // Empty state if none enrolled
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    visible: SecurityService.enrolledFingers.length === 0

                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("No fingerprints enrolled yet. Click \"Enroll New Fingerprint\" below.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOutlineVariant
                    }
                }

                // Repeater for enrolled fingers
                Repeater {
                    model: SecurityService.enrolledFingers
                    delegate: Rectangle {
                        required property string modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.8)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 10

                            MaterialSymbol {
                                text: "fingerprint"
                                iconSize: 22
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: SecurityService.getFingerDisplayName(modelData)
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer0
                            }

                            StyledText {
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOutlineVariant
                            }

                            // Test verification button
                            RippleButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.verysmall
                                onClicked: SecurityService.startVerify(modelData)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "check_circle"
                                    iconSize: 18
                                    color: Appearance.colors.colOutlineVariant
                                }
                                StyledToolTip { text: Translation.tr("Test verify this fingerprint") }
                            }

                            // Delete button
                            RippleButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.verysmall
                                onClicked: {
                                    root.deleteConfirmFinger = modelData;
                                    root.showDeleteDialog = true;
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete_outline"
                                    iconSize: 18
                                    color: Appearance.colors.colError
                                }
                                StyledToolTip { text: Translation.tr("Delete this fingerprint") }
                            }
                        }
                    }
                }
            }

            // Live Verification Feedback Banner
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: verifyLayout.implicitHeight + 14
                visible: SecurityService.isVerifying
                radius: Appearance.rounding.small
                color: SecurityService.verifyMatched
                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                    : (SecurityService.verifyFailed
                        ? ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                        : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5))
                border.width: 1
                border.color: SecurityService.verifyMatched
                    ? Appearance.colors.colPrimary
                    : (SecurityService.verifyFailed ? Appearance.colors.colError : Appearance.colors.colOutline)

                RowLayout {
                    id: verifyLayout
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    MaterialSymbol {
                        text: SecurityService.verifyMatched ? "check_circle" : (SecurityService.verifyFailed ? "error" : "sensors")
                        iconSize: 20
                        color: SecurityService.verifyMatched
                            ? Appearance.colors.colPrimary
                            : (SecurityService.verifyFailed ? Appearance.colors.colError : Appearance.colors.colOnLayer0)
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: SecurityService.verifyMessage
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }

                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.verysmall
                        onClicked: SecurityService.cancelVerify()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOutlineVariant
                        }
                    }
                }
            }

            // Actions Row: Enroll Button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: SecurityService.available

                RippleButton {
                    implicitHeight: 38
                    implicitWidth: enrollBtnLayout.implicitWidth + 20
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: {
                        root.showEnrollDialog = true;
                    }

                    contentItem: RowLayout {
                        id: enrollBtnLayout
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "add"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            text: Translation.tr("Enroll New Fingerprint")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                RippleButton {
                    implicitHeight: 38
                    implicitWidth: verifyAllBtnLayout.implicitWidth + 20
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    visible: SecurityService.enrolledFingers.length > 0
                    onClicked: SecurityService.startVerify()

                    contentItem: RowLayout {
                        id: verifyAllBtnLayout
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "fingerprint"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            text: Translation.tr("Test Verification")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ================= 3. PASSWORD MANAGEMENT =================
        ContentSection {
            icon: "lock"
            title: Translation.tr("Change Password")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                // Current Password Input
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Current Password")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: currentPassField.activeFocus
                            ? Appearance.colors.colPrimary
                            : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 4

                            TextField {
                                id: currentPassField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignVCenter
                                echoMode: root.showCurrentPassword ? TextInput.Normal : TextInput.Password
                                placeholderText: Translation.tr("Enter current password")
                                placeholderTextColor: Appearance.colors.colOutlineVariant
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.normal
                                selectByMouse: true
                                background: null
                                text: root.currentPasswordInput
                                onTextChanged: root.currentPasswordInput = text
                            }

                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.verysmall
                                onClicked: root.showCurrentPassword = !root.showCurrentPassword

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.showCurrentPassword ? "visibility_off" : "visibility"
                                    iconSize: 17
                                    color: Appearance.colors.colOutlineVariant
                                }
                            }
                        }
                    }
                }

                // New Password Input
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("New Password")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: newPassField.activeFocus
                            ? Appearance.colors.colPrimary
                            : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 4

                            TextField {
                                id: newPassField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignVCenter
                                echoMode: root.showNewPassword ? TextInput.Normal : TextInput.Password
                                placeholderText: Translation.tr("Enter new password")
                                placeholderTextColor: Appearance.colors.colOutlineVariant
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.normal
                                selectByMouse: true
                                background: null
                                text: root.newPasswordInput
                                onTextChanged: root.newPasswordInput = text
                            }

                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.verysmall
                                onClicked: root.showNewPassword = !root.showNewPassword

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.showNewPassword ? "visibility_off" : "visibility"
                                    iconSize: 17
                                    color: Appearance.colors.colOutlineVariant
                                }
                            }
                        }
                    }
                }

                // Confirm Password Input
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Confirm New Password")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: confirmPassField.activeFocus
                            ? Appearance.colors.colPrimary
                            : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 4

                            TextField {
                                id: confirmPassField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignVCenter
                                echoMode: root.showConfirmPassword ? TextInput.Normal : TextInput.Password
                                placeholderText: Translation.tr("Re-enter new password")
                                placeholderTextColor: Appearance.colors.colOutlineVariant
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.normal
                                selectByMouse: true
                                background: null
                                text: root.confirmPasswordInput
                                onTextChanged: root.confirmPasswordInput = text
                            }

                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.verysmall
                                onClicked: root.showConfirmPassword = !root.showConfirmPassword

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.showConfirmPassword ? "visibility_off" : "visibility"
                                    iconSize: 17
                                    color: Appearance.colors.colOutlineVariant
                                }
                            }
                        }
                    }

                    // Password Match Indicator
                    RowLayout {
                        spacing: 4
                        visible: root.confirmPasswordInput.length > 0

                        MaterialSymbol {
                            text: (root.newPasswordInput === root.confirmPasswordInput) ? "check" : "close"
                            iconSize: 14
                            color: (root.newPasswordInput === root.confirmPasswordInput)
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colError
                        }

                        StyledText {
                            text: (root.newPasswordInput === root.confirmPasswordInput)
                                ? Translation.tr("Passwords match")
                                : Translation.tr("Passwords do not match")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: (root.newPasswordInput === root.confirmPasswordInput)
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colError
                        }
                    }
                }

                // Feedback Message Banner
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: passMsgLayout.implicitHeight + 14
                    visible: SecurityService.passwordChangeSuccess || SecurityService.passwordChangeError.length > 0
                    radius: Appearance.rounding.small
                    color: SecurityService.passwordChangeSuccess
                        ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                        : ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                    border.width: 1
                    border.color: SecurityService.passwordChangeSuccess
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colError

                    RowLayout {
                        id: passMsgLayout
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        MaterialSymbol {
                            text: SecurityService.passwordChangeSuccess ? "check_circle" : "error"
                            iconSize: 20
                            color: SecurityService.passwordChangeSuccess
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colError
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: SecurityService.passwordChangeSuccess
                                ? SecurityService.passwordChangeMessage
                                : SecurityService.passwordChangeError
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                // Submit Button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        implicitHeight: 38
                        implicitWidth: updatePassBtnLayout.implicitWidth + 24
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        enabled: root.currentPasswordInput.length > 0 &&
                                 root.newPasswordInput.length > 0 &&
                                 root.newPasswordInput === root.confirmPasswordInput &&
                                 !SecurityService.isChangingPassword
                        opacity: enabled ? 1.0 : 0.5
                        onClicked: {
                            SecurityService.changePassword(root.currentPasswordInput, root.newPasswordInput);
                        }

                        contentItem: RowLayout {
                            id: updatePassBtnLayout
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: SecurityService.isChangingPassword ? "hourglass_empty" : "key"
                                iconSize: 18
                                color: Appearance.colors.colOnPrimary
                            }

                            StyledText {
                                text: SecurityService.isChangingPassword
                                    ? Translation.tr("Updating...")
                                    : Translation.tr("Update Password")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }

        // ================= 4. LOCKSCREEN & PAM INTEGRATION =================
        ContentSection {
            icon: "shield"
            title: Translation.tr("Lock Screen & System Integration")

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: pamInfoLayout.implicitHeight + 20
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: pamInfoLayout
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    MaterialSymbol {
                        text: "verified_user"
                        iconSize: 26
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: Translation.tr("Biometric Lock Screen Authentication")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            text: Translation.tr("Quickshell Lock Screen and SDDM are configured to accept fingerprint authentication automatically whenever at least one finger is enrolled.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOutlineVariant
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    // ================= ENROLLMENT WIZARD MODAL DIALOG =================
    Rectangle {
        id: enrollModalOverlay
        anchors.fill: parent
        visible: root.showEnrollDialog
        color: "#99000000"
        z: 99

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(480, parent.width - 40)
            implicitHeight: modalMainCol.implicitHeight + 36
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ColumnLayout {
                id: modalMainCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 16

                // Modal Header
                RowLayout {
                    Layout.fillWidth: true

                    MaterialSymbol {
                        text: "fingerprint"
                        iconSize: 24
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: SecurityService.isEnrolling
                            ? Translation.tr("Enrolling %1").arg(SecurityService.getFingerDisplayName(SecurityService.enrollingFinger))
                            : Translation.tr("Select Finger to Enroll")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        onClicked: {
                            if (SecurityService.isEnrolling) {
                                SecurityService.cancelEnrollment();
                            }
                            root.showEnrollDialog = false;
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 18
                            color: Appearance.colors.colOutlineVariant
                        }
                    }
                }

                // Step 1: Finger Selection (when not yet actively enrolling)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !SecurityService.isEnrolling
                    spacing: 10

                    StyledText {
                        text: Translation.tr("Choose which finger you would like to register:")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOutlineVariant
                    }

                    // Finger Selector Grid
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: SecurityService.supportedFingers
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool isEnrolled: SecurityService.isFingerEnrolled(modelData.id)
                                readonly property bool isSelected: root.selectedFingerToEnroll === modelData.id

                                Layout.fillWidth: true
                                implicitHeight: 36
                                radius: Appearance.rounding.verysmall
                                color: isSelected
                                    ? Appearance.colors.colPrimary
                                    : (isEnrolled ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0)
                                border.width: isSelected ? 0 : 1
                                border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedFingerToEnroll = modelData.id;
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    MaterialSymbol {
                                        text: isEnrolled ? "check_circle" : "fingerprint"
                                        iconSize: 16
                                        color: isSelected ? Appearance.colors.colOnPrimary : (isEnrolled ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant)
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: isSelected ? Font.Medium : Font.Normal
                                        color: isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                                    }

                                    StyledText {
                                        visible: isEnrolled
                                        text: Translation.tr("Enrolled")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOutlineVariant
                                    }
                                }
                            }
                        }
                    }

                    // Start Enrollment Action Button
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 8

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            implicitHeight: 38
                            implicitWidth: startEnrollBtnLayout.implicitWidth + 24
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: {
                                SecurityService.startEnrollment(root.selectedFingerToEnroll);
                            }

                            contentItem: RowLayout {
                                id: startEnrollBtnLayout
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    text: "play_arrow"
                                    iconSize: 18
                                    color: Appearance.colors.colOnPrimary
                                }

                                StyledText {
                                    text: Translation.tr("Start Enrollment")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }
                }

                // Step 2: Interactive Live Sensor Progress (while enrolling)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: SecurityService.isEnrolling
                    spacing: 16

                    // Central Fingerprint & Circular Progress
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 120
                        implicitHeight: 120

                        CircularProgress {
                            anchors.fill: parent
                            lineWidth: 5
                            implicitSize: 120
                            value: SecurityService.enrollTotalStages > 0
                                ? (SecurityService.enrollStage / SecurityService.enrollTotalStages)
                                : 0
                            colPrimary: Appearance.colors.colPrimary
                            colSecondary: Appearance.colors.colLayer1
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            implicitWidth: 96
                            implicitHeight: 96
                            radius: Appearance.rounding.full
                            color: SecurityService.enrollCompleted
                                ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                                : Appearance.colors.colLayer1

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: SecurityService.enrollCompleted ? "check_circle" : "fingerprint"
                                iconSize: 48
                                color: SecurityService.enrollCompleted
                                    ? Appearance.colors.colPrimary
                                    : (SecurityService.enrollStage > 0 ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant)

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }
                    }

                    // Stage Counter Badge
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: stageBadgeText.implicitWidth + 18
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer1

                        StyledText {
                            id: stageBadgeText
                            anchors.centerIn: parent
                            text: SecurityService.enrollCompleted
                                ? Translation.tr("Complete!")
                                : Translation.tr("Stage %1 of %2").arg(SecurityService.enrollStage).arg(SecurityService.enrollTotalStages)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: SecurityService.enrollCompleted ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        }
                    }

                    // Live Instructional Text
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: SecurityService.enrollMessage
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                        wrapMode: Text.WordWrap
                    }

                    // Error text if any
                    StyledText {
                        Layout.fillWidth: true
                        visible: SecurityService.enrollError.length > 0
                        horizontalAlignment: Text.AlignHCenter
                        text: SecurityService.enrollError
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colError
                        wrapMode: Text.WordWrap
                    }

                    // Modal Action Buttons
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            implicitHeight: 36
                            implicitWidth: 90
                            buttonRadius: Appearance.rounding.small
                            colBackground: SecurityService.enrollCompleted ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                            colBackgroundHover: SecurityService.enrollCompleted ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                            onClicked: {
                                if (SecurityService.isEnrolling) {
                                    SecurityService.cancelEnrollment();
                                }
                                root.showEnrollDialog = false;
                            }

                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: SecurityService.enrollCompleted ? Translation.tr("Done") : Translation.tr("Cancel")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: SecurityService.enrollCompleted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= DELETE CONFIRMATION DIALOG =================
    Rectangle {
        id: deleteModalOverlay
        anchors.fill: parent
        visible: root.showDeleteDialog
        color: "#99000000"
        z: 99

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(380, parent.width - 40)
            implicitHeight: deleteModalCol.implicitHeight + 36
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ColumnLayout {
                id: deleteModalCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: "warning"
                        iconSize: 22
                        color: Appearance.colors.colError
                    }
                    StyledText {
                        text: Translation.tr("Delete Fingerprint?")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Are you sure you want to remove \"%1\"? You will no longer be able to unlock your system with this finger.").arg(SecurityService.getFingerDisplayName(root.deleteConfirmFinger))
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOutlineVariant
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        implicitHeight: 34
                        implicitWidth: 80
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: root.showDeleteDialog = false

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Cancel")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    RippleButton {
                        implicitHeight: 34
                        implicitWidth: 80
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colError
                        colBackgroundHover: Appearance.colors.colError
                        onClicked: {
                            SecurityService.deleteFingerprint(root.deleteConfirmFinger);
                            root.showDeleteDialog = false;
                        }

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Delete")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnError
                        }
                    }
                }
            }
        }
    }
}
