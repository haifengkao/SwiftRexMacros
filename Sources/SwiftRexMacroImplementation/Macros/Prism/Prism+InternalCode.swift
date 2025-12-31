import Foundation
import SwiftSyntax

extension EnumCaseElementListSyntax.Element {
    var predicate: VariableDeclSyntax {
        VariableDeclSyntax(
            bindingSpecifier: TokenSyntax.keyword(.var),
            bindings: PatternBindingListSyntax {
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: TokenSyntax(stringLiteral: "is\(name.text.uppercaseFirst())")).with(\.leadingTrivia, .space),
                    typeAnnotation: .from(Bool.self),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(CodeBlockItemListSyntax {
                        `if`(caseLet: caseNameToken, equalsTo: .`self`) {
                            BooleanLiteralExprSyntax(booleanLiteral: true)
                        } else: {
                            BooleanLiteralExprSyntax(booleanLiteral: false)
                        }
                    }))
                )
            }
        )
    }

    var prism: VariableDeclSyntax {
        VariableDeclSyntax(
            bindingSpecifier: TokenSyntax.keyword(.var),
            bindings: PatternBindingListSyntax {
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: caseNameToken).with(\.leadingTrivia, .space),
                    typeAnnotation: TypeAnnotationSyntax(type: parameterClause.formattedType().︖),
                    accessorBlock: AccessorBlockSyntax(accessors: extractedAssociatedValues())
                )
            }
        )
    }
}

extension EnumCaseElementListSyntax.Element {
    private var caseNameToken: TokenSyntax {
        .identifier(name.text)
    }

    func extractedAssociatedValues() -> AccessorBlockSyntax.Accessors {
        guard let associatedValues = parameterClause else {
            return .getter(
                .block{
                    `if`(caseLet: caseNameToken, equalsTo: .`self`) {
                        voidTuple()
                    } else: {
                        Syntax.`nil`
                    }
                }
            )
        }

        let associatedValueNames: [(isNamed: Bool, name: TokenSyntax, nameOrIndex: TokenSyntax)] = associatedValues.parameters.enumerated().map { index, param in
            let indexToken = "\(index)".asToken
            if let firstName = param.firstName {
                if firstName.tokenKind == .wildcard {
                    let bindingName = param.secondName?.text ?? "associatedValue\(index)"
                    return (isNamed: false, name: bindingName.asToken, nameOrIndex: indexToken)
                }
                let name = firstName.text
                return (isNamed: true, name: name.asToken, nameOrIndex: name.asToken)
            }

            return (isNamed: false, name: "associatedValue\(index)".asToken, nameOrIndex: indexToken)
        }

        let value = "value".asToken
        let newValue = "newValue".asToken

        return .accessors(
            get: {
                if associatedValueNames.count == 1 {
                    `guard`(`case`(let: caseNameToken, bindings: [value], equalsTo: .`self`), else: {
                        ReturnStmtSyntax(expression: Syntax.`nil`)
                    })

                    ReturnStmtSyntax(expression: DeclReferenceExprSyntax(baseName: value))
                } else {
                    let values = associatedValueNames.map(\.name)
                    `guard`(`case`(let: caseNameToken, bindings: values, equalsTo: .`self`), else: {
                        ReturnStmtSyntax(expression: Syntax.`nil`)
                    })
                    ReturnStmtSyntax(
                        expression: TupleExprSyntax(elements: .init(
                            associatedValueNames.mapIdentifyingLast { associatedValue, isLast in
                                LabeledExprSyntax(
                                    label: associatedValue.isNamed ? associatedValue.name : nil,
                                    colon: associatedValue.isNamed ? TokenSyntax(.colon, presence: .present) : nil,
                                    expression: DeclReferenceExprSyntax(baseName: associatedValue.name)
                                ).with(\.trailingComma, isLast ? nil : TokenSyntax(.comma, presence: .present))
                            }
                        ))

                    )
                }
            },
            set: {
                `guard` {
                    `case`(let: caseNameToken, equalsTo: .`self`)

                    OptionalBindingConditionSyntax(
                        bindingSpecifier: .keyword(.let),
                        pattern: IdentifierPatternSyntax(identifier: newValue),
                        initializer: InitializerClauseSyntax(value: DeclReferenceExprSyntax(baseName: newValue))
                    )
                } else: {
                    ReturnStmtSyntax()
                }

                if associatedValueNames.count == 1 {
                    InfixOperatorExprSyntax(
                        leftOperand: DeclReferenceExprSyntax(baseName: .`self`),
                        operator: AssignmentExprSyntax(),
                        rightOperand: `case`(
                            caseNameToken,
                            setters: associatedValueNames.map { (label: $0.isNamed ? $0.name.text : nil, identifier: newValue) }
                        )
                    )
                } else {
                    InfixOperatorExprSyntax(
                        leftOperand: DeclReferenceExprSyntax(baseName: .`self`),
                        operator: AssignmentExprSyntax(),
                        rightOperand: `case`(
                            caseNameToken,
                            setters: associatedValueNames.map {
                                (
                                    label: $0.isNamed ? $0.name.text : nil,
                                    expression: MemberAccessExprSyntax.init(base: DeclReferenceExprSyntax(baseName: newValue), declName: DeclReferenceExprSyntax(baseName: $0.nameOrIndex))
                                )
                            }
                        )
                    )
                }
            }
        )
    }
}

extension Optional<EnumCaseParameterClauseSyntax> {
    func formattedType() -> TypeSyntaxProtocol {
        guard
            let associatedValues = self?.parameters,
            let first = associatedValues.first
        else { return .from(Void.self) }

        if associatedValues.count == 1 {
            return first.type.trimmedType
        }

        return TupleTypeSyntax(elements: TupleTypeElementListSyntax(
            associatedValues.map(\.tupleElement).mapIdentifyingLast { type, isLast in
                type.with(\.trailingComma, isLast ? nil : TokenSyntax(TokenKind.comma, presence: .present))
            }
        ))
    }
}

extension EnumCaseParameterListSyntax.Element {
    var tupleElement: TupleTypeElementSyntax {
        if let firstName, firstName.tokenKind != .wildcard {
            return TupleTypeElementSyntax(firstName: .identifier(firstName.text), colon: TokenSyntax(.colon, presence: .present), type: type.trimmedType)
        }

        return TupleTypeElementSyntax(type: type.trimmedType)
    }
}
