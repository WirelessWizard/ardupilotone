// -*- tab-width: 4; Mode: C++; c-basic-offset: 4; indent-tabs-mode: t -*-
//
// This is free software; you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation; either version 2.1 of the License, or (at
// your option) any later version.
//

/// @file	AP_MetaClass.h
///	@brief	An abstract base class from which other classes can inherit.
///
/// This abstract base class declares and implements functions that are
/// useful to code that wants to know things about a class, or to operate
/// on the class without knowing precisely what it is.
///
/// All classes that inherit from this class can be assumed to have these
/// basic functions.
///

#ifndef AP_METACLASS_H
#define AP_METACLASS_H

#include <stddef.h>			// for size_t
#include <inttypes.h>

#include <avr/io.h>			// for RAMEND

/// Basic meta-class from which other AP_* classes can derive.
///
/// Functions that form the public API to the metaclass are prefixed meta_.
///
class AP_MetaClass
{
public:
	/// Default constructor does nothing.
	AP_MetaClass(void);

	/// Default destructor is virtual, to ensure that all subclasses'
	/// destructors are virtual.  This guarantees that all destructors
	/// in the inheritance chain are called at destruction time.
	///
	virtual ~AP_MetaClass();

	/// Typedef for the ID unique to all instances of a class.
	///
	/// See ::meta_type_id for a discussion of class type IDs.
	///
	typedef uint16_t	AP_TypeID;

	/// Obtain a value unique to all instances of a specific subclass.
	///
	/// The value can be used to determine whether two class pointers
	/// refer to the same exact class type.  The value can also be cached
	/// and then used to detect objects of a given type at a later point.
	///
	/// This is similar to the basic functionality of the C++ typeid
	/// keyword, but does not depend on std::type_info or any compiler-
	/// generated RTTI.
	///
	/// The value is derived from the vtable address, so it is guaranteed
	/// to be unique but cannot be known until the program has been compiled
	/// and linked.  Thus, the only way to know the type ID of a given
	/// type is to construct an object at runtime.  To cache the type ID
	/// of a class Foo, one would write:
	///
	/// AP_MetaClass::AP_TypeID	Foo_type_id;
	///
	/// { Foo a; Foo_type_id = a.meta_type_id(); }
	///
	/// This will construct a temporary Foo object a and save its type ID.
	///
	/// @param	p				A pointer to an instance of a subclass of AP_MetaClass.
	/// @return					A type-unique value.
	///
	AP_TypeID					meta_type_id(void) const {
		return *(AP_TypeID *)this;
	}

	/// External handle for an instance of an AP_MetaClass subclass, contains
	/// enough information to construct and validate a pointer to the instance
	/// when passed back from an untrusted source.
	///
	/// Handles are useful when passing a reference to an object to a client outside
	/// the system, as they can be validated by the system when the client hands
	/// them back.
	///
	typedef uint32_t	AP_MetaHandle;

	/// Return a value that can be used as an external pointer to an instance
	/// of a subclass.
	///
	/// The value can be passed to an untrusted agent, and validated on its return.
	///
	/// The value contains the 16-bit type ID of the actual class and
	/// a pointer to the class instance.
	///
	/// @return					An opaque handle
	///
	AP_MetaHandle				meta_get_handle(void) const	{
		return ((AP_MetaHandle)meta_type_id() << 16) | (uint16_t)this;
	}

	/// Validates an AP_MetaClass handle.
	///
	/// The value of the handle is not required to be valid; in particular the
	/// pointer encoded in the handle is validated before being dereferenced.
	///
	/// The handle is considered good if the pointer is valid and the object
	/// it points to has a type ID that matches the ID in the handle.
	///
	/// @param	handle			A possible AP_MetaClass handle
	/// @return					The instance pointer if the handle is good,
	///							or NULL if it is bad.
	///
	static AP_MetaClass			*meta_validate_handle(AP_MetaHandle handle) {
		AP_MetaClass	*candidate = (AP_MetaClass *)(handle & 0xffff);	// extract object pointer
		uint16_t		id = handle >> 16;								// and claimed type

		// Sanity-check the pointer to ensure it lies within the device RAM, so that
		// a bad handle won't cause ::meta_type_id to read outside of SRAM.
		// Assume that RAM (or addressable storage of some sort, at least) starts at zero.
		//
		// Note that this implies that we cannot deal with objects in ROM or EEPROM,
		// but the constructor wouldn't be able to populate a vtable pointer there anyway...
		//
		if ((uint16_t)candidate >= (RAMEND - 2))	// -2 to account for the type_id
			return NULL;

		// Compare the typeid of the object that candidate points to with the typeid
		// from the handle.  Note that it's safe to call meta_type_id() off the untrusted
		// candidate pointer because meta_type_id is non-virtual (and will in fact be
		// inlined here).
		//
		if (candidate->meta_type_id() == id)
			return candidate;

		return NULL;
	}

	/// Tests whether two objects are of precisely the same class.
	///
	/// Note that in the case where p2 inherits from p1, or vice-versa, this will return
	/// false as we cannot detect these inheritance relationships at runtime.
	///
	/// In the caller's context, p1 and p2 may be pointers to any type, but we require
	/// that they be passed as pointers to AP_MetaClass in order to make it clear that
	/// they should be pointers to classes derived from AP_MetaClass.
	///
	/// No attempt is made to validate whether p1 and p2 are actually derived from
	/// AP_MetaClass.  If p1 and p2 are equal, or if they point to non-class objects with
	/// similar contents, or to non-AP_MetaClass derived classes with no virtual functions
	/// this function may return true.
	///
	/// @param	p1				The first object to be compared.
	/// @param	p2				The second object to be compared.
	/// @return					True if the two objects are of the same class, false
	///							if they are not.
	///
	static bool					meta_type_equivalent(AP_MetaClass *p1, AP_MetaClass *p2) {
		return p1->meta_type_id() == p2->meta_type_id();
	}

	/// Cast a pointer to an expected class type.
	///
	/// This function is used when a pointer is expected to be a pointer to a
	/// subclass of AP_MetaClass, but the caller is not certain.  It will return the pointer
	/// if it is, or NULL if it is not a pointer to the expected class.
	///
	/// This should be used with caution, as _typename's default constructor and
	/// destructor will be run, possibly introducing undesired side-effects.
	///
	/// @todo	Consider whether we should make it difficult to have a default constructor
	///			with appreciable side-effects.
	///
	/// @todo	Check whether we need to reinterpret_cast to get the right return type.
	///
	/// @param	_p				An AP_MetaClass subclass whose type is to be tested.
	/// @param	_typename		The name of a type with which _p is to be compared.
	/// @return					True if _p is of type _typename, false otherwise.
	///
	template<typename T>
	static T* meta_cast(AP_MetaClass *p) {
		T	tmp;
		if (meta_type_equivalent(p, &tmp))
			return (T *)p;
		return NULL;
	}

	/// Serialize the class.
	///
	/// Serialization stores the state of the class in an external buffer in such a
	/// fashion that it can later be restored by unserialization.
	///
	/// AP_MetaClass subclasses should only implement these functions if saving and
	/// restoring their state makes sense.
	///
	/// Serialization provides a mechanism for exporting the state of the class to an
	/// external consumer, either for external introspection or for subsequent restoration.
	///
	/// Classes that wrap variables should define the format of their serialiaed data
	/// so that external consumers can reliably interpret it.
	///
	/// @param	buf				Buffer into which serialised data should be placed.
	/// @param	bufSize			The size of the buffer provided.
	/// @return					The size of the serialised data, even if that data would
	///							have overflowed the buffer.  If the return value is zero,
	///							the class does not support serialization.
	///
	virtual size_t				serialize(void *buf, size_t bufSize) const;

	/// Unserialize the class.
	///
	/// Unserializing a class from a buffer into which the class previously serialized
	/// itself restores the instance to an identical state, where "identical" is left
	/// up to the class itself to define.
	///
	/// Classes that wrap variables should define the format of their serialized data so
	/// that external providers can reliably encode it.
	///
	/// @param	buf				Buffer containing serialized data.
	/// @param	bufSize			The size of the buffer.
	/// @return					The number of bytes from the buffer that would be consumed
	///							unserializing the data.  If the value is less than or equal
	///							to bufSize, unserialization was successful.  If the return
	///							value is zero the class does not support unserialisation or
	///							the data in the buffer is invalid.
	///
	virtual size_t				unserialize(void *buf, size_t bufSize);
};

#endif // AP_METACLASS_H