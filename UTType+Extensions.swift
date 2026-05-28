//
//  UTType+Extensions.swift
//  dulcinea
//
//  Created by Dominic Mauro on 6/11/25.
//

import UniformTypeIdentifiers

// NOTE: `UTType.epub` is already declared by the system `UniformTypeIdentifiers`
// framework (available since iOS 14). Redeclaring it here caused an
// "invalid redeclaration of 'epub'" compile error, which blocked the whole
// build. The custom extension has been removed — all `[.epub]` usages now
// resolve to the system-provided type.
