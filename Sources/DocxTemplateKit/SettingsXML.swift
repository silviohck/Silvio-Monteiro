import Foundation

/// Ajustes em `word/settings.xml`.
enum SettingsXML {
    /// Elementos que, pela ordem exigida pelo formato do Word, vêm depois de `<w:printTwoOnOne/>`.
    private static let elementsAfter = [
        "w:strictFirstAndLastChars", "w:noLineBreaksAfter", "w:noLineBreaksBefore", "w:savePreviewPicture",
        "w:doNotValidateAgainstSchema", "w:saveInvalidXml", "w:ignoreMixedContent", "w:alwaysShowPlaceholderText",
        "w:doNotDemarcateInvalidXml", "w:saveXmlDataOnly", "w:useXSLTWhenSaving", "w:saveThroughXslt",
        "w:showXMLTags", "w:alwaysMergeEmptyNamespace", "w:updateFields", "w:hdrShapeDefaults", "w:footnotePr",
        "w:endnotePr", "w:compat", "w:docVars", "w:rsids", "m:mathPr", "w:attachedSchema", "w:themeFontLang",
        "w:clrSchemeMapping", "w:doNotIncludeSubdocsInStats", "w:doNotAutoCompressPictures", "w:forceUpgrade",
        "w:captions", "w:readModeInkLockDown", "w:smartTagType", "sl:schemaLibrary", "w:shapeDefaults",
        "w:doNotEmbedSmartTags", "w:decimalSymbol", "w:listSeparator", "w14:", "w15:", "w16",
    ]

    /// Liga "2 páginas por folha" (`<w:printTwoOnOne/>`), inserido na posição que o Word espera.
    static func withTwoPagesPerSheet(_ xml: String) -> String {
        guard !xml.contains("<w:printTwoOnOne") else { return xml }
        var position = xml.range(of: "</w:settings>")?.lowerBound
        for element in elementsAfter {
            if let range = xml.range(of: "<" + element), position.map({ range.lowerBound < $0 }) ?? true {
                position = range.lowerBound
            }
        }
        guard let position else { return xml }
        var result = xml
        result.insert(contentsOf: "<w:printTwoOnOne/>", at: position)
        return result
    }
}
