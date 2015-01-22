// Copyright (c) 2014, the Dart Team. All rights reserved. Use of this
// source code is governed by a BSD-style license that can be found in
// the LICENSE file.

library reflectable.src.implementation;

@dm.MirrorsUsed(
    /* symbols: '*', */  // Symbols passed to getName, Strings to new Symbol.
    /* targets: '*', */  // Targets that may be accessed reflectively.
    metaTargets: '*',    // Implies reflective access when used as metadata
    override: '*')       // Libraries for which this holds (here: all).
import 'dart:mirrors' as dm;

import 'dart:collection';

import 'package:logging/logging.dart';
import 'package:code_transformers/resolver.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/resolver.dart';

import '../reflectable.dart';
import '../mirror.dart';

var _logger = new Logger('reflectable.reflectable');

// ----------------------------------------------------------------------
// Methods supporting the implementation of Reflectable

InstanceMirror reflect(o) {
  return wrapInstanceMirror(dm.reflect(o));
}

ClassMirror reflectClass(Type t) {
  return wrapClassMirror(dm.reflectClass(t));
}

LibraryMirror findLibrary(Symbol libraryName) {
  return new _LibraryMirrorImpl(dm.currentMirrorSystem()
                                .findLibrary(libraryName));
}

Map<Uri, LibraryMirror> get libraries {
  Map<Uri, dm.LibraryMirror> libs = dm.currentMirrorSystem().libraries;
  return new Map<Uri, LibraryMirror>.fromIterable(
      libs.keys,
      key: (k) => k,
      value: (k) => new _LibraryMirrorImpl(libs[k]));
}

LibraryMirror get mainLibrary {
  Map<Uri, dm.LibraryMirror> libs = dm.currentMirrorSystem().libraries;
  for (var lib in libs) {
    Map<Symbol, dm.DeclarationMirror> decls = lib.declarations;
    for (var decl in decls) {
      if (decl.simpleName == #main) {
        if (decl is dm.MethodMirror && decl.isRegularMethod) {
          return new _LibraryMirrorImpl(lib);
        }
      }
    }
  }
  // No such library exists.
  return null;
}

ClassMirror wrapClassMirror(dm.ClassMirror m) {
  if (m is dm.FunctionTypeMirror) {
    // TODO(eernst): return new _FunctionTypeMirrorImpl(cm);
    return new _ClassMirrorImpl(m); // Temporary solution, will mostly work.
  }
  else if (m is dm.ClassMirror) {
    return new _ClassMirrorImpl(m);
  }
  else {
    // TODO(eernst): make error reporting consistent
    throw "unexpected subtype of ClassMirror";
  }
}

DeclarationMirror wrapDeclarationMirror(dm.DeclarationMirror m) {
  if (m is dm.MethodMirror) {
    return new _MethodMirrorImpl(m);
  }
  else if (m is dm.ParameterMirror) {
    return new _ParameterMirrorImpl(m);
  }
  else if (m is dm.VariableMirror) {
    return new _VariableMirrorImpl(m);
  }
  else if (m is dm.TypeVariableMirror) {
    // TODO(eernst): return new _TypeVariableMirrorImpl(m);
    throw "not yet implemented";
  }
  else if (m is dm.TypedefMirror) {
    // TODO(eernst): return new _TypeDefMirrorImpl(m);
    throw "not yet implemented";
  }
  else if (m is dm.ClassMirror) { // Covers FunctionTypeMirror and ClassMirror.
    return wrapClassMirror(m);
  }
  else if (m is dm.LibraryMirror) {
    return new _LibraryMirrorImpl(m);
  }
  else {
    // TODO(eernst): make error reporting consistent
    throw "unexpected subtype of DeclarationMirror";
  }
}

InstanceMirror wrapInstanceMirror(dm.InstanceMirror m) {
  if (m is dm.ClosureMirror) {
    // TODO(eernst): return new _ClosureMirrorImpl(m);
    throw "not yet implemented";
  }
  else if (m is dm.InstanceMirror) {
    return new _InstanceMirrorImpl(m);
  }
  else {
    // TODO(eernst): make error reporting consistent
    throw "unexpected subtype of InstanceMirror";
  }
}

ObjectMirror wrapObjectMirror(dm.ObjectMirror m) {
  if (m is dm.LibraryMirror) {
    return new _LibraryMirrorImpl(m);
  }
  else if (m is dm.InstanceMirror) {
    return wrapInstanceMirror(m);
  }
  else if (m is dm.ClassMirror) {
    return wrapClassMirror(m);
  }
  else {
    // TODO(eernst): make error reporting consistent
    throw "unexpected subtype of ObjectMirror";
  }
}

TypeMirror wrapTypeMirror(dm.TypeMirror m) {
  if (m is dm.TypeVariableMirror) {
    // TODO(eernst): return new _TypeVariableMirrorImpl(m);
    throw "not yet implemented";
  }
  else if (m is dm.TypedefMirror) {
    // TODO(eernst): return new _TypedefMirrorImpl(m);
    throw "not yet implemented";
  }
  else if (m is dm.ClassMirror) {
    return wrapClassMirror(m);
  }
  else {
    // TODO(eernst): make error reporting consistent
    throw "unexpected subtype of TypeMirror";
  }
}

dm.ClassMirror unwrapClassMirror(ClassMirror m) {
  // else if (m is _FunctionTypeMirrorImpl) ...
  // else
  if (m is _ClassMirrorImpl) {
    return m._classMirror;
  }
  else {
    // TODO(eernst): make error reporting consistent
    throw "unexpected subtype of ClassMirror";
  }
}

dm.TypeMirror unwrapTypeMirror(TypeMirror m) {
  // TODO(eernst):
  // if (m is _TypeVariableMirrorImpl) ...
  // else if (m is _TypedefMirrorImpl) ...
  if (m is _ClassMirrorImpl) {
    return m._classMirror;
  }
  else {
    // TODO(eernst): make error reporting consistent
    throw "unexpected subtype of TypeMirror";
  }
}

/// Checks whether the given [type] is this class, based on the
/// high probability that any class containing a static const
/// named thisClassId with the value given above is this one.
/// The [resolver] is used to retrieve the dart.core library
/// such that constant evaluation can take place on the
/// thisClassId of the target program.
bool _isThisClass(Resolver resolver, ClassElement type) {
  FieldElement idField = type.getField("thisClassId");
  if (idField == null || !idField.isStatic) return false;
  if (idField is ConstFieldElementImpl) {
    // FIXME: It seems inappropriate to use this low-level
    // approach, but I cannot easily see how to avoid it.
    LibraryElement coreLibrary = resolver.getLibraryByName("dart.core");
    TypeProvider typeProvider = new TypeProviderImpl(coreLibrary);
    DartObject dartObjectThisClassId =
        new DartObjectImpl(typeProvider.stringType,
                           new StringState(ReflectableX.thisClassId));
    EvaluationResultImpl idResult = idField.evaluationResult;
    if (idResult is ValidResult) {
      DartObject idValue = idResult.value;
      return idValue == dartObjectThisClassId;
    }
  }
  // Not a const field, cannot be the right class.
  return false;
}

/// Returns the ClassElement in the target program which
/// corresponds to this class.  The [resolver] is used to
/// get the library for this code in the target program
/// (if present), and the dart.core library for constant
/// evaluation.
ClassElement _getClassElement(Resolver resolver) {
  LibraryElement lib = resolver.getLibraryByName("reflectable.reflectable");
  if (lib == null) return null;
  List<CompilationUnitElement> units = lib.units;
  for (var unit in units) {
    List<ClassElement> types = unit.types;
    for (var type in types) {
      if (type.name == ReflectableX.thisClassName &&
          _isThisClass(resolver, type)) {
        return type;
      }
    }
  }
  // This class not found in target program.
  return null;
}

/// Returns true iff [classElement] is [focusClass] or a subclass of thereof.
bool _isRelevantClass(ClassElement classElement,
                             ClassElement focusClass) {
  if (classElement == focusClass) return true;
  return classElement
      .allSupertypes
      .any((type) => type.element == focusClass);
}

/// Returns true iff the [elementAnnotation] is an
/// instance of [focusClass] or a subclass thereof.
bool _isRelevantAnnotation(ElementAnnotation elementAnnotation,
                                  ClassElement focusClass) {
  if (elementAnnotation.element != null) {
    Element element = elementAnnotation.element;
    if (element is ConstructorElement) {
      if (_isRelevantClass(element.enclosingElement, focusClass)) {
        return true;
      }
      // else fall through to false: not a relevant annotation.
    }
    // else fall through to false: only constructor expressions handled (now).
  }
  return false;
}

List<ClassElement> classes(Resolver resolver) {
  ClassElement focusClass = _getClassElement(resolver);
  if (focusClass == null) return [];
  Iterable<LibraryElement> libs = resolver.libraries;
  List<ClassElement> result = new List<ClassElement>();
  for (var lib in libs) {
    List<CompilationUnitElement> units = lib.units;
    for (var unit in units) {
      List<ClassElement> types = unit.types;
      for (var type in types) {
        List<ElementAnnotation> metadata = type.metadata;
        for (var mdItem in metadata) {
          if (_isRelevantAnnotation(mdItem, focusClass)) {
            result.add(type);
          }
        }
      }
    }
  }
  return result;
}

// ----------------------------------------------------------------------
// Mirror Implementation Classes.

abstract class _ObjectMirrorImplMixin implements ObjectMirror {
  dm.ObjectMirror get _objectMirror;

  Object invoke(Symbol memberName,
                List positionalArguments,
                [Map<Symbol,dynamic> namedArguments]) {
    return _objectMirror
        .invoke(memberName,positionalArguments,namedArguments)
        .reflectee;
  }

  Object getField(Symbol fieldName) =>
      _objectMirror.getField(fieldName).reflectee;

  Object setField(Symbol fieldName, Object value) =>
      _objectMirror.setField(fieldName, value).reflectee;
}

class _LibraryMirrorImpl extends _DeclarationMirrorImpl
                         with _ObjectMirrorImplMixin
                         implements LibraryMirror {
  dm.LibraryMirror get _libraryMirror => _declarationMirror;
  dm.ObjectMirror get _objectMirror => _declarationMirror as dm.ObjectMirror;

  _LibraryMirrorImpl(dm.LibraryMirror m) : super(m) {}

  Uri get uri => _libraryMirror.uri;

  Map<Symbol, DeclarationMirror> get declarations {
    Map<Symbol, dm.DeclarationMirror> decls = _libraryMirror.declarations;
    Iterable<Symbol> relevantKeys = decls.keys.where((k) {
        List<dm.InstanceMirror> metadata = decls[k].metadata;
        for (var item in metadata) {
          if (item.hasReflectee && item.reflectee is ReflectableX) return true;
        }
        return false;
      });
    return new Map<Symbol, DeclarationMirror>.fromIterable(
        relevantKeys,
        key: (k) => k,
        value: (v) => wrapDeclarationMirror(decls[v]));
  }

  bool operator == (other) => other is _LibraryMirrorImpl
      ? _libraryMirror == other._libraryMirror
      : false;

  List<LibraryDependencyMirror> get libraryDependencies =>
      _libraryMirror.libraryDependencies
      .map((dep) => new _LibraryDependencyMirrorImpl(dep))
      .toList();

  String toString() => "_LibraryMirrorImpl('${_libraryMirror.toString()}')";
}

class _LibraryDependencyMirrorImpl implements LibraryDependencyMirror {
  final dm.LibraryDependencyMirror _libraryDependencyMirror;

  _LibraryDependencyMirrorImpl(this._libraryDependencyMirror);

  bool get isImport => _libraryDependencyMirror.isImport;

  bool get isExport => _libraryDependencyMirror.isExport;

  LibraryMirror get sourceLibrary =>
      new _LibraryMirrorImpl(_libraryDependencyMirror.sourceLibrary);

  LibraryMirror get targetLibrary =>
      new _LibraryMirrorImpl(_libraryDependencyMirror.targetLibrary);

  Symbol get prefix => _libraryDependencyMirror.prefix;

  List<Object> get metadata =>
      _libraryDependencyMirror.metadata
      .map((m) => m.reflectee)
      .toList();

  String toString() =>
      "_LibraryDependencyMirrorImpl('${_libraryDependencyMirror.toString()}')";
}

class _InstanceMirrorImpl extends _ObjectMirrorImplMixin
                          implements InstanceMirror {
  final dm.InstanceMirror _instanceMirror;
  dm.ObjectMirror get _objectMirror => _instanceMirror;

  _InstanceMirrorImpl(this._instanceMirror);

  TypeMirror get type => wrapTypeMirror(_instanceMirror.type);

  bool get hasReflectee => _instanceMirror.hasReflectee;

  get reflectee => _instanceMirror.reflectee;

  bool operator == (other) => other is _InstanceMirrorImpl
      ? _instanceMirror == other._instanceMirror
      : false;

  delegate(Invocation invocation) => _instanceMirror.delegate(invocation);

  String toString() => "_InstanceMirrorImpl('${_instanceMirror.toString()}')";
}

class _ClassMirrorImpl extends _DeclarationMirrorImpl
                       with _ObjectMirrorImplMixin
                       implements ClassMirror {
  dm.ClassMirror get _classMirror => _declarationMirror;
  dm.ObjectMirror get _objectMirror => _classMirror;

  _ClassMirrorImpl(dm.ClassMirror cm) : super(cm) {}

  bool get hasReflectedType => _classMirror.hasReflectedType;

  Type get reflectedType => _classMirror.reflectedType;

  List<TypeVariableMirror> get typeVariables =>
      // TODO(eernst): _classMirror.typeVariables
      // .map((v) => new _TypeVariableMirrorImpl(v))
      // .toList();
      throw "not yet implemented";

  List<TypeMirror> get typeArguments =>
      _classMirror.typeArguments
      .map((a) => wrapTypeMirror(a))
      .toList();

  bool get isOriginalDeclaration =>
      _classMirror.isOriginalDeclaration;

  TypeMirror get originalDeclaration =>
      wrapTypeMirror(_classMirror.originalDeclaration);

  bool isSubtypeOf(TypeMirror other) =>
      _classMirror.isSubtypeOf(unwrapTypeMirror(other));

  bool isAssignableTo(TypeMirror other) =>
      _classMirror.isAssignableTo(unwrapTypeMirror(other));

  TypeMirror get superclass {
    dm.ClassMirror sup = _classMirror.superclass;
    if (sup == null) return null;
    return wrapClassMirror(sup);
  }

  bool get isAbstract => _classMirror.isAbstract;

  Map<Symbol, DeclarationMirror> get declarations {
    // TODO(eernst): Consider whether metadata should be used to filter.
    Map<Symbol, dm.DeclarationMirror> decls = _classMirror.declarations;
    return new Map<Symbol, DeclarationMirror>.fromIterable(
        decls.keys,
        key: (k) => k,
        value: (v) => wrapDeclarationMirror(decls[v]));
  }

  Map<Symbol, MethodMirror> get instanceMembers {
    // TODO(eernst): Consider whether metadata should be used to filter.
    Map<Symbol, dm.MethodMirror> members = _classMirror.instanceMembers;
    return new Map<Symbol, MethodMirror>.fromIterable(
        members.keys,
        key: (k) => k,
        value: (v) => new _MethodMirrorImpl(members[v]));
  }

  Map<Symbol, MethodMirror> get staticMembers {
    // TODO(eernst): Consider whether metadata should be used to filter.
    Map<Symbol, dm.MethodMirror> members = _classMirror.staticMembers;
    return new Map<Symbol, MethodMirror>.fromIterable(
        members.keys,
        key: (k) => k,
        value: (v) => new _MethodMirrorImpl(members[v]));
  }

  TypeMirror get mixin => wrapTypeMirror(_classMirror.mixin);

  Object newInstance(Symbol constructorName,
                     List positionalArguments,
                     [Map<Symbol,dynamic> namedArguments]) {
    return _classMirror
        .newInstance(constructorName, positionalArguments, namedArguments)
        .reflectee;
  }

  bool operator == (other) => other is _ClassMirrorImpl
      ? _classMirror == other._classMirror
      : false;

  bool isSubclassOf(ClassMirror other) =>
      // TODO(eernst)!!
      _classMirror.isSubclassOf(unwrapClassMirror(other));

  TypeMirror get type => wrapTypeMirror(_classMirror);

  String toString() => "_ClassMirrorImpl('${_classMirror.toString()}')";
}

abstract class _DeclarationMirrorImpl implements DeclarationMirror {
  final dm.DeclarationMirror _declarationMirror;

  _DeclarationMirrorImpl(this._declarationMirror);

  Symbol get simpleName => _declarationMirror.simpleName;

  Symbol get qualifiedName => _declarationMirror.qualifiedName;

  DeclarationMirror get owner =>
      wrapDeclarationMirror(_declarationMirror.owner);

  bool get isPrivate => _declarationMirror.isPrivate;

  bool get isTopLevel => _declarationMirror.isTopLevel;

  // Currently skip 'SourceLocation get location;'.

  List<Object> get metadata =>
      _declarationMirror.metadata
      .map((m) => m.reflectee)
      .toList();

  TypeMirror get type {
    var decl = _declarationMirror;  // For conciseness.
    if (decl is dm.MethodMirror && decl.isRegularMethod) {
      // TODO(eernst):  This currently follows the semantics of the
      // same getter in pkg/smoke/lib/mirrors.dart, _MirrorDeclaration,
      // but should surely be extended to deliver the function type.
      return wrapTypeMirror(dm.reflectClass(Function));
    }
    dm.TypeMirror tm = decl is dm.VariableMirror ? decl.type : decl.returnType;
    return wrapTypeMirror(tm);
  }

  String toString() =>
      "_DeclarationMirrorImpl('${_declarationMirror.toString()}')";
}

class _MethodMirrorImpl extends _DeclarationMirrorImpl implements MethodMirror {
  dm.MethodMirror get _methodMirror => _declarationMirror;

  _MethodMirrorImpl(dm.MethodMirror mm) : super(mm) {}

  TypeMirror get returnType => wrapTypeMirror(_methodMirror.returnType);

  String get source => _methodMirror.source;

  List<ParameterMirror> get parameters =>
      _methodMirror.parameters
      .map((p) => new _ParameterMirrorImpl(p))
      .toList();

  bool get isStatic => _methodMirror.isStatic;

  bool get isAbstract => _methodMirror.isAbstract;

  bool get isSynthetic => _methodMirror.isSynthetic;

  bool get isRegularMethod => _methodMirror.isRegularMethod;

  bool get isOperator => _methodMirror.isOperator;

  bool get isGetter => _methodMirror.isGetter;

  bool get isSetter => _methodMirror.isSetter;

  bool get isConstructor => _methodMirror.isConstructor;

  Symbol get constructorName => _methodMirror.constructorName;

  bool get isConstConstructor => _methodMirror.isConstConstructor;

  bool get isGenerativeConstructor => _methodMirror.isGenerativeConstructor;

  bool get isRedirectingConstructor => _methodMirror.isRedirectingConstructor;

  bool get isFactoryConstructor => _methodMirror.isFactoryConstructor;

  bool operator == (other) => other is _MethodMirrorImpl
      ? _methodMirror == other._methodMirror
      : false;

  String toString() => "_MethodMirrorImpl('${_methodMirror.toString()}')";
}

class _VariableMirrorImpl extends _DeclarationMirrorImpl
                          implements VariableMirror {
  dm.VariableMirror get _variableMirror => _declarationMirror;

  _VariableMirrorImpl(dm.VariableMirror vm) : super(vm) {}

  TypeMirror get type => wrapTypeMirror(_variableMirror.type);

  bool get isStatic => _variableMirror.isStatic;

  bool get isFinal => _variableMirror.isFinal;

  bool get isConst => _variableMirror.isConst;

  bool operator == (other) => other is _VariableMirrorImpl
      ? _variableMirror == other._variableMirror
      : false;

  String toString() => "_VariableMirrorImpl('${_variableMirror.toString()}')";
}

class _ParameterMirrorImpl extends _VariableMirrorImpl
                           implements ParameterMirror {
  dm.ParameterMirror get _parameterMirror => _declarationMirror;

  _ParameterMirrorImpl(dm.ParameterMirror pm) : super(pm) {}

  bool get isOptional => _parameterMirror.isOptional;

  bool get isNamed => _parameterMirror.isNamed;

  bool get hasDefaultValue => _parameterMirror.hasDefaultValue;

  Object get defaultValue => _parameterMirror.defaultValue.reflectee;

  bool operator == (other) => other is _ParameterMirrorImpl
      ? _parameterMirror == other._parameterMirror
      : false;

  String toString() => "_ParameterMirrorImpl('${_parameterMirror.toString()}')";
}

// ----------------------------------------------------------------------
// Auxiliary convenience material, making smoke code more portable.

/// Used by _safeSuperclass.
final _objectType = dm.reflectClass(Object);

/// Returns a mirror of the immediate superclass of [type], defaulting to
/// Object if no other supertype can be found; never returns null.
/// This method was copied from smoke/lib/mirrors.dart and adjusted.
dm.ClassMirror _safeSuperclass(dm.ClassMirror type) {
  try {
    var t = type.superclass;
    if (t != null && t.owner != null && t.owner.isPrivate) t = _objectType;
    return t;
  } on UnsupportedError catch (e) {
    return _objectType;
  }
}

class _SuperTypeIterator extends Iterator <dm.ClassMirror> {
  bool firstInvocation = true;  // At first [moveNext] starts; at end: noop.
  dm.ClassMirror _initialClassMirror;
  dm.ClassMirror _currentClassMirror = null;  // [null] initially and at end.

  _SuperTypeIterator(this._initialClassMirror);

  bool moveNext() {
    if (firstInvocation) {
      // Start iterating.
      firstInvocation = false;
      _currentClassMirror = _initialClassMirror;
      return true;
    }
    if (_currentClassMirror == _objectType) {
      // Cannot go further.
      _currentClassMirror = null;
      return false;
    } else {
      // Find the next super class and make that [current].
      _currentClassMirror = _safeSuperclass(_currentClassMirror);
      return true;
    }
  }

  dm.ClassMirror get current => _currentClassMirror;
}

class _SuperTypeIterable extends IterableMixin<dm.ClassMirror> {
  dm.ClassMirror _initialClassMirror;

  _SuperTypeIterable(this._initialClassMirror);

  Iterator<dm.ClassMirror> get iterator {
    return new _SuperTypeIterator(_initialClassMirror);
  }
}

/// Returns a mirror of the declaration of [member], if the mirrored
/// entity is an instance of a class and such a declaration exists in
/// that class or one of its superclasses; otherwise returns null.
dm.DeclarationMirror _getDeclaration(dm.ClassMirror m, Symbol member) {
  // Search up through all superclasses for the requested declaration.
  for (dm.ClassMirror cm in new _SuperTypeIterable(m)) {
    dm.DeclarationMirror decl = cm.declarations[member];
    if (decl != null) return decl;
  }
  // No such declaration in any superclass.
  return null;
}

/// Returns a mirror of the declaration of [member], if the mirrored
/// entity is an instance of a class and such a declaration exists;
/// otherwise returns null.
dm.DeclarationMirror _getInstanceDeclaration(InstanceMirror m, Symbol member) {
  var typeMirror = (m as _InstanceMirrorImpl)._instanceMirror.type;
  if (typeMirror is! dm.ClassMirror) return null;
  // Search up through all superclasses for the requested declaration.
  for (dm.ClassMirror cm in new _SuperTypeIterable(typeMirror)) {
    dm.DeclarationMirror decl = cm.declarations[member];
    if (decl != null) return decl;
  }
  // No such declaration in any superclass.
  return null;
}

bool canGet(ClassMirror cm, Symbol name) {
  Map<Symbol, DeclarationMirror> decls = cm.declarations;
  DeclarationMirror m = decls[name];
  if (m != null) {
    dm.DeclarationMirror dmd = (m as _DeclarationMirrorImpl)._declarationMirror;
    if (dmd is dm.VariableMirror
        || (dmd is dm.MethodMirror && dmd.isRegularMethod)
        || (dmd is dm.MethodMirror && dmd.isGetter)
        || (dmd is dm.MethodMirror && dmd.isStatic)) {
      return true;
    }
  }
  if (cm.superclass == null) {
    return false;
  } else {
    return canGet(cm.superclass, name);
  }
}

Symbol setterName(Symbol getter) =>
    new Symbol('${dm.MirrorSystem.getName(getter)}=');

bool _canSetUsingVariable(ClassMirror cm, Symbol name) {
  Map<Symbol, DeclarationMirror> decls = cm.declarations;
  DeclarationMirror m = decls[name];
  if (m != null) {
    dm.DeclarationMirror dmm = (m as _DeclarationMirrorImpl)._declarationMirror;
    if (dmm is dm.VariableMirror && !dmm.isFinal) return true;
  }
  if (cm.superclass == null) {
    return false;
  } else {
    return _canSetUsingVariable(cm.superclass, name);
  }
}

bool _canSetUsingSetter(ClassMirror cm, Symbol name) {
  dm.DeclarationMirror dmm =
      _getDeclaration((cm as _ClassMirrorImpl)._classMirror, setterName(name));
  return dmm != null;
}

bool canSet(ClassMirror cm, Symbol name) {
  if (_canSetUsingVariable(cm, name)) return true;
  return _canSetUsingSetter(cm, name);
}

/// Returns a mirror of the declaration of [member], if the mirrored
/// entity is an instance of a class and such a declaration exists in that
/// class or one of its superclasses except Object; otherwise returns null.
dm.DeclarationMirror _getDeclarationExceptObject(dm.ClassMirror initial_cm,
                                                 Symbol member) {
  // Search up through all superclasses for the requested declaration.
  for (dm.ClassMirror cm in new _SuperTypeIterable(initial_cm)) {
    if (cm == _objectType) return null;
    dm.DeclarationMirror decl = cm.declarations[member];
    if (decl != null) return decl;
  }
  // No such declaration in any superclass.
  return null;
}

bool hasNoSuchMethod(ClassMirror cm) {
  dm.DeclarationMirror decl =
      _getDeclarationExceptObject((cm as _ClassMirrorImpl)._classMirror,
                                  #noSuchMethod);
  return decl is dm.MethodMirror && decl.isRegularMethod;
}

bool hasInstanceMethod(ClassMirror cm, Symbol member) {
  // Semantics following pkg/smoke/lib/mirrors.dart, except that we _do_
  // include declarations in Object (which makes a difference for noSuchMethod
  // and toString).
  dm.DeclarationMirror decl =
      _getDeclaration((cm as _ClassMirrorImpl)._classMirror, member);
  return decl is dm.MethodMirror && decl.isRegularMethod && !decl.isStatic;
}

/// Returns a mirror of the declaration of [member], if the mirrored
/// entity is a class and such a declaration exists in that class
/// (superclasses are not considered); otherwise returns null.
dm.DeclarationMirror _getLocalDeclaration(dm.ClassMirror cm, Symbol member) {
  return cm.declarations[member];
}

bool hasStaticMethod(ClassMirror cm, Symbol member) {
  // Semantics following pkg/smoke/lib/mirrors.dart.
  dm.DeclarationMirror decl =
      _getLocalDeclaration((cm as _ClassMirrorImpl)._classMirror, member);
  return decl is dm.MethodMirror && decl.isRegularMethod && decl.isStatic;
}

DeclarationMirror getDeclaration(ClassMirror cm, Symbol name) {
  dm.DeclarationMirror decl =
      _getLocalDeclaration((cm as _ClassMirrorImpl)._classMirror, name);
  if (decl == null) return null;
  return wrapDeclarationMirror(decl);
}

bool isField(DeclarationMirror m) {
  return m is VariableMirror;
}

bool isFinal(DeclarationMirror m) {
  return m is VariableMirror && m.isFinal;
}

bool isMethod(DeclarationMirror m) {
  // Might need to follow the semantics of smoke/lib/smoke.dart
  // Declaration.isMethod, which is just a test for [kind == METHOD]
  // where [kind] is selected when the Declaration is created.
  // TODO(eernst): find the precise semantics of this method,
  // and implement it.  The current implementation does pass the
  // tests in common.dart.
  return m is MethodMirror && m.isRegularMethod;
}

List<LibraryMirror> _filterDeps(LibraryMirror lm,
                                bool filter(LibraryDependency)) {
  return lm.libraryDependencies
      .where(filter)
      .map((dep) => dep.targetLibrary)
      .toList();
}

List<LibraryMirror> imports(LibraryMirror lm) =>
    _filterDeps(lm, (dep) => dep.isImport);

List<LibraryMirror> exports(LibraryMirror lm) =>
    _filterDeps(lm, (dep) => dep.isExport);

bool isProperty(DeclarationMirror m) =>
    m is MethodMirror && !m.isRegularMethod;